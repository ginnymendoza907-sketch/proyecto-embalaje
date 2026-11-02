CREATE OR REPLACE PROCEDURE analitico.ejecutar_elt()
LANGUAGE plpgsql AS $$
DECLARE
    v_stg INT;
    v_fact INT;
BEGIN
    -- EXTRACT + LOAD: copia de los datos operacionales a staging
    TRUNCATE analitico.stg_sector, analitico.stg_cliente,
             analitico.stg_material, analitico.stg_producto,
             analitico.stg_tipo_cambio, analitico.stg_orden_compra,
             analitico.stg_factura, analitico.stg_factura_detalle;

    INSERT INTO analitico.stg_sector SELECT * FROM operacional.sector;
    INSERT INTO analitico.stg_cliente SELECT * FROM operacional.cliente;
    INSERT INTO analitico.stg_material SELECT * FROM operacional.material;
    INSERT INTO analitico.stg_producto SELECT * FROM operacional.producto;
    INSERT INTO analitico.stg_tipo_cambio SELECT * FROM operacional.tipo_cambio;
    INSERT INTO analitico.stg_orden_compra SELECT * FROM operacional.orden_compra;
    INSERT INTO analitico.stg_factura SELECT * FROM operacional.factura;
    INSERT INTO analitico.stg_factura_detalle SELECT * FROM operacional.factura_detalle;

    -- TRANSFORM: staging a dimensiones y tabla de hechos
    TRUNCATE analitico.fact_ventas, analitico.dim_producto,
             analitico.dim_cliente, analitico.dim_fecha;

    INSERT INTO analitico.dim_producto
        (id_producto, codigo, descripcion, tipo_producto, material, test)
    SELECT p.id_producto, UPPER(TRIM(p.codigo)), TRIM(p.descripcion),
           p.tipo_producto, m.nombre, p.test
    FROM analitico.stg_producto p
    JOIN analitico.stg_material m ON m.id_material = p.id_material;

    INSERT INTO analitico.dim_cliente
        (id_cliente, nombre, sector, tipo_cliente)
    SELECT c.id_cliente, TRIM(c.nombre), s.nombre, c.tipo_cliente
    FROM analitico.stg_cliente c
    JOIN analitico.stg_sector s ON s.id_sector = c.id_sector;

    INSERT INTO analitico.dim_fecha
        (fecha, anio, mes, nombre_mes, trimestre, semana, anio_mes)
    SELECT d::date, EXTRACT(YEAR FROM d)::INT, EXTRACT(MONTH FROM d)::INT,
        (ARRAY['Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio', 'Agosto',
               'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'])[EXTRACT(MONTH FROM d)::INT],
        EXTRACT(QUARTER FROM d)::INT, EXTRACT(WEEK FROM d)::INT, TO_CHAR(d, 'YYYY-MM')
    FROM generate_series(
        (SELECT LEAST(MIN(fecha_oc), (SELECT MIN(fecha) FROM analitico.stg_tipo_cambio))
         FROM analitico.stg_orden_compra)::timestamp,
        GREATEST(
            CURRENT_DATE,
            (SELECT MAX(fecha_factura) FROM analitico.stg_factura),
            (SELECT MAX(fecha) FROM analitico.stg_tipo_cambio)
        )::timestamp,
        INTERVAL '1 day'
    ) AS d;

    INSERT INTO analitico.fact_ventas
        (id_detalle, id_factura, fecha, fecha_oc, dias_oc_factura,
         id_producto, id_cliente, moneda, cantidad, precio_unitario,
         tc_factura, tc_oc, ingreso_crc, ingreso_crc_tc_oc,
         efecto_cambiario_crc, costo_crc, margen_crc, margen_pct)
    SELECT b.id_detalle, b.id_factura, b.fecha, b.fecha_oc, (b.fecha - b.fecha_oc),
        b.id_producto, b.id_cliente, b.moneda, b.cantidad, b.precio_unitario,
        b.tc_f, b.tc_o,
        ROUND(b.ingreso_mon * b.tc_f, 2),
        ROUND(b.ingreso_mon * b.tc_o, 2),
        ROUND(b.ingreso_mon * (b.tc_f - b.tc_o), 2),
        ROUND(b.costo, 2),
        ROUND(b.ingreso_mon * b.tc_f - b.costo, 2),
        CASE WHEN b.ingreso_mon * b.tc_f = 0 THEN 0
             ELSE ROUND((b.ingreso_mon * b.tc_f - b.costo) / (b.ingreso_mon * b.tc_f), 4)
        END
    FROM (
        SELECT fd.id_detalle, f.id_factura, f.fecha_factura AS fecha,
            oc.fecha_oc, fd.id_producto, oc.id_cliente, oc.moneda,
            fd.cantidad, fd.precio_unitario, f.tipo_cambio_aplicado AS tc_f,
            CASE WHEN oc.moneda = 'USD'
                 THEN COALESCE(tco.compra, f.tipo_cambio_aplicado)
                 ELSE 1
            END AS tc_o,
            fd.cantidad * fd.precio_unitario AS ingreso_mon,
            fd.cantidad * fd.costo_unitario_crc AS costo
        FROM analitico.stg_factura_detalle fd
        JOIN analitico.stg_factura f ON f.id_factura = fd.id_factura
        JOIN analitico.stg_orden_compra oc ON oc.id_oc = f.id_oc
        LEFT JOIN LATERAL (
            SELECT t.compra
            FROM analitico.stg_tipo_cambio t
            WHERE t.fecha <= oc.fecha_oc
            ORDER BY t.fecha DESC
            LIMIT 1
        ) tco ON TRUE
    ) b;

    -- CONTROL DE CALIDAD Y BITÁCORA
    SELECT COUNT(*) INTO v_stg FROM analitico.stg_factura_detalle;
    SELECT COUNT(*) INTO v_fact FROM analitico.fact_ventas;

    IF v_stg <> v_fact THEN
        RAISE EXCEPTION 'ELT inconsistente: % filas en staging y % en hechos', v_stg, v_fact;
    END IF;

    INSERT INTO analitico.elt_log (filas_staging, filas_hechos)
    VALUES (v_stg, v_fact);
END;
$$;

-- Tipo de cambio de equilibrio por producto
CREATE OR REPLACE VIEW analitico.v_tc_equilibrio AS
WITH precio AS (
    SELECT fd.id_producto,
        SUM(fd.cantidad * fd.precio_unitario) / SUM(fd.cantidad) AS precio_usd_prom
    FROM operacional.factura_detalle fd
    JOIN operacional.factura f ON f.id_factura = fd.id_factura
    JOIN operacional.orden_compra oc ON oc.id_oc = f.id_oc
    WHERE oc.moneda = 'USD'
    GROUP BY fd.id_producto
)
SELECT p.id_producto, p.codigo, p.descripcion,
    ROUND(pr.precio_usd_prom, 4) AS precio_usd_prom,
    ROUND(operacional.costo_producto(p.id_producto, CURRENT_DATE), 2) AS costo_actual_crc,
    ROUND(operacional.costo_producto(p.id_producto, CURRENT_DATE)
        / (pr.precio_usd_prom * (1 - par.valor)), 2) AS tc_equilibrio,
    tc.compra AS tc_actual
FROM operacional.producto p
JOIN precio pr ON pr.id_producto = p.id_producto
CROSS JOIN analitico.parametro par
CROSS JOIN operacional.v_tc_actual tc
WHERE par.nombre = 'margen_objetivo';

-- Primera carga para que el esquema analítico tenga datos
CALL analitico.ejecutar_elt();