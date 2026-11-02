-- 1. CATALOGOS

INSERT INTO operacional.sector (nombre)
VALUES
    ('Farmacéutica'),
    ('Agrícola'),
    ('Tecnológica'),
    ('Alimenticia');

INSERT INTO operacional.cliente (nombre, id_sector, tipo_cliente)
SELECT v.nombre, s.id_sector, v.tipo
FROM (
    VALUES
        ('Laboratorios Meridian', 'Farmacéutica', 'Externo'),
        ('FarmaCentro',            'Farmacéutica', 'Externo'),
        ('Agrícola Tropical',      'Agrícola',     'Externo'),
        ('Fincas del Valle',       'Agrícola',     'Externo'),
        ('TecnoPack CR',           'Tecnológica',  'Externo'),
        ('ElectroParts',           'Tecnológica',  'Externo'),
        ('Alimentos del Sol',      'Alimenticia',  'Externo'),
        ('Planta Hermana',         'Alimenticia',  'Interno')
) AS v(nombre, sector, tipo)
JOIN operacional.sector s
    ON s.nombre = v.sector;

INSERT INTO operacional.material (nombre)
VALUES
    ('Kraft'),
    ('Medium'),
    ('Duplex');

-- 2. PRODUCTOS

INSERT INTO operacional.producto
    (codigo, descripcion, tipo_producto, id_material,
     largo_mm, ancho_mm, alto_mm, test)
SELECT
    v.codigo, v.descripcion, v.tipo, m.id_material,
    v.l, v.a, v.h, v.t
FROM (
    VALUES
        ('CC-001', 'Caja corrugada 40x30x30 Kraft', 'Caja corrugada', 'Kraft', 400, 300, 300, 200),
        ('CC-002', 'Caja corrugada 50x40x40 Kraft', 'Caja corrugada', 'Kraft', 500, 400, 400, 275),
        ('CC-003', 'Caja corrugada 60x40x40 Kraft', 'Caja corrugada', 'Kraft', 600, 400, 400, 275),
        ('CC-004', 'Caja corrugada 30x20x20 Medium', 'Caja corrugada', 'Medium', 300, 200, 200, 150),
        ('CC-005', 'Caja corrugada 40x30x25 Medium', 'Caja corrugada', 'Medium', 400, 300, 250, 200),
        ('CC-006', 'Caja corrugada 50x35x35 Medium', 'Caja corrugada', 'Medium', 500, 350, 350, 200),
        ('CC-007', 'Caja corrugada 45x45x45 Kraft', 'Caja corrugada', 'Kraft', 450, 450, 450, 275),
        ('CC-008', 'Caja corrugada 35x25x25 Kraft', 'Caja corrugada', 'Kraft', 350, 250, 250, 200),
        ('CD-001', 'Caja Duplex 30x30x10', 'Caja Duplex', 'Duplex', 300, 300, 100, 150),
        ('CD-002', 'Caja Duplex 40x30x15', 'Caja Duplex', 'Duplex', 400, 300, 150, 150),
        ('CD-003', 'Caja Duplex 25x25x25', 'Caja Duplex', 'Duplex', 250, 250, 250, 150),
        ('CD-004', 'Caja Duplex 50x30x20', 'Caja Duplex', 'Duplex', 500, 300, 200, 175),
        ('SP-001', 'Separador 40x30', 'Separador', 'Medium', 400, 300, NULL, NULL),
        ('SP-002', 'Separador 50x40', 'Separador', 'Medium', 500, 400, NULL, NULL),
        ('SP-003', 'Separador 30x20', 'Separador', 'Medium', 300, 200, NULL, NULL)
) AS v(codigo, descripcion, tipo, material, l, a, h, t)
JOIN operacional.material m
    ON m.nombre = v.material;

-- 3. INSUMOS

INSERT INTO operacional.insumo (nombre, unidad)
VALUES
    ('Papel Kraft', 'kg'), ('Papel Medium', 'kg'), ('Papel Duplex', 'kg'),
    ('Almidón', 'kg'), ('Tinta flexográfica', 'litro'), ('Pegamento', 'kg');

-- 4. COSTOS DE INSUMOS (Precio inicial y dos aumentos: febrero y junio)

INSERT INTO operacional.costo_insumo
    (id_insumo, fecha_vigencia, costo_unitario_crc)
SELECT i.id_insumo, v.fecha, ROUND(b.base * v.factor, 4)
FROM operacional.insumo i
JOIN (
    VALUES
        ('Papel Kraft', 650), ('Papel Medium', 520), ('Papel Duplex', 720),
        ('Almidón', 480), ('Tinta flexográfica', 3200), ('Pegamento', 900)
) AS b(nombre, base) ON b.nombre = i.nombre
CROSS JOIN (
    VALUES
        (DATE '2025-11-01', 1.00), (DATE '2026-02-01', 1.04), (DATE '2026-06-01', 1.09)
) AS v(fecha, factor);

-- 5. RECETAS DE PRODUCTOS (Papel según el material utilizado)

INSERT INTO operacional.producto_insumo
    (id_producto, id_insumo, cantidad_por_unidad)
SELECT p.id_producto, i.id_insumo,
    CASE
        WHEN p.tipo_producto = 'Separador'
        THEN ROUND((p.largo_mm * p.ancho_mm) / 1000000.0 * 0.9, 4)
        ELSE ROUND((p.largo_mm*p.ancho_mm + 2*p.largo_mm*p.alto_mm + 2*p.ancho_mm*p.alto_mm) / 1000000.0 * 0.9, 4)
    END
FROM operacional.producto p
JOIN operacional.material m ON m.id_material = p.id_material
JOIN operacional.insumo i ON i.nombre = 'Papel ' || m.nombre;

-- Almidón, pegamento y tinta (No se utilizan en los separadores)
INSERT INTO operacional.producto_insumo
    (id_producto, id_insumo, cantidad_por_unidad)
SELECT p.id_producto, i.id_insumo, x.cant
FROM operacional.producto p
CROSS JOIN (
    VALUES ('Almidón', 0.03), ('Pegamento', 0.01), ('Tinta flexográfica', 0.002)
) AS x(nombre, cant)
JOIN operacional.insumo i ON i.nombre = x.nombre
WHERE p.tipo_producto <> 'Separador';

-- 6. TIPO DE CAMBIO DIARIO (Baja gradual aproximada de 520 a 455 colones)
INSERT INTO operacional.tipo_cambio (fecha, compra, venta)
SELECT fecha, compra, compra + 6.00
FROM (
    SELECT
        d::date AS fecha,
        ROUND((520 - 65.0 * (d::date - DATE '2025-11-01') / 364
        + 2.0 * SIN((d::date - DATE '2025-11-01') / 6.0))::numeric, 2) AS compra
    FROM generate_series(
        TIMESTAMP '2025-11-01', TIMESTAMP '2026-10-31', INTERVAL '1 day'
    ) AS d
) t;

-- 7. GENERACIÓN DE 120 ÓRDENES DE COMPRA
DO $$
DECLARE
    v_hoy CONSTANT DATE := DATE '2026-10-28';
    v_cli INT; v_nom TEXT; v_mon CHAR(3); v_n INT;
    v_fecha_oc DATE; v_fecha_ent DATE; v_fecha_fac DATE;
    v_oc INT; v_fac INT; v_estado VARCHAR(20);
BEGIN
    PERFORM setseed(0.42);
    FOR i IN 1..120 LOOP
        v_fecha_oc := DATE '2025-11-03' + FLOOR(RANDOM() * 340)::INT;
        v_fecha_ent := v_fecha_oc + 14 + FLOOR(RANDOM() * 21)::INT;
        v_fecha_fac := v_fecha_ent + FLOOR(RANDOM() * 6)::INT;
        v_n := 1 + FLOOR(RANDOM() * 4)::INT;

        SELECT id_cliente, nombre INTO v_cli, v_nom
        FROM operacional.cliente ORDER BY RANDOM() LIMIT 1;

        v_mon := CASE WHEN v_nom IN (
            'Laboratorios Meridian', 'Agrícola Tropical', 'TecnoPack CR', 'Alimentos del Sol'
        ) THEN 'USD' ELSE 'CRC' END;

        v_estado := CASE
            WHEN i % 40 = 0 THEN 'Anulada'
            WHEN v_fecha_fac <= v_hoy THEN 'Pendiente'
            ELSE 'En producción'
        END;

        INSERT INTO operacional.orden_compra
            (numero_oc, id_cliente, fecha_oc, fecha_entrega, moneda, estado)
        VALUES (
            'OC-' || LPAD(i::TEXT, 4, '0'), v_cli, v_fecha_oc, v_fecha_ent, v_mon, v_estado
        ) RETURNING id_oc INTO v_oc;

        INSERT INTO operacional.oc_detalle
            (id_oc, id_producto, cantidad, precio_unitario)
        SELECT v_oc, p.id_producto, (500 + FLOOR(RANDOM() * 20) * 250)::INT,
            CASE
                WHEN v_mon = 'USD'
                THEN ROUND(operacional.costo_producto(p.id_producto, DATE '2025-11-01') / 0.70 / 520, 2)
                ELSE ROUND(operacional.costo_producto(p.id_producto, DATE '2025-11-01') / 0.72, 2)
            END
        FROM (SELECT id_producto FROM operacional.producto ORDER BY RANDOM() LIMIT v_n) p;

        IF v_estado = 'Pendiente' THEN
            INSERT INTO operacional.factura (numero_factura, id_oc, fecha_factura)
            VALUES ('F-' || LPAD(i::TEXT, 5, '0'), v_oc, v_fecha_fac)
            RETURNING id_factura INTO v_fac;

            INSERT INTO operacional.factura_detalle
                (id_factura, id_producto, cantidad, precio_unitario)
            SELECT v_fac, id_producto, cantidad, precio_unitario
            FROM operacional.oc_detalle WHERE id_oc = v_oc;
        END IF;
    END LOOP;
END $$;