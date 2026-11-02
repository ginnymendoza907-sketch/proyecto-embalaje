CREATE OR REPLACE VIEW operacional.v_tc_actual AS
SELECT fecha, compra, venta
FROM operacional.tipo_cambio
WHERE fecha <= CURRENT_DATE
ORDER BY fecha DESC LIMIT 1;

CREATE OR REPLACE VIEW operacional.v_producto_costo_actual AS
SELECT p.id_producto, p.codigo, p.descripcion, p.tipo_producto,
       m.nombre AS material,
       operacional.costo_producto(p.id_producto, CURRENT_DATE) AS costo_actual_crc
FROM operacional.producto p
JOIN operacional.material m ON m.id_material = p.id_material
WHERE p.activo;

CREATE OR REPLACE VIEW operacional.v_oc_resumen AS
SELECT oc.id_oc, oc.numero_oc, cl.nombre AS cliente,
       oc.fecha_oc, oc.fecha_entrega, oc.moneda, oc.estado,
       COALESCE(SUM(d.cantidad * d.precio_unitario), 0) AS total_moneda
FROM operacional.orden_compra oc
JOIN operacional.cliente cl ON cl.id_cliente = oc.id_cliente
LEFT JOIN operacional.oc_detalle d ON d.id_oc = oc.id_oc
GROUP BY oc.id_oc, oc.numero_oc, cl.nombre,
         oc.fecha_oc, oc.fecha_entrega, oc.moneda, oc.estado;

CREATE OR REPLACE VIEW operacional.v_oc_pendientes AS
SELECT * FROM operacional.v_oc_resumen
WHERE estado IN ('Pendiente', 'En producción');

CREATE OR REPLACE VIEW operacional.v_factura_resumen AS
SELECT f.id_factura, f.numero_factura, f.fecha_factura,
       oc.numero_oc, cl.nombre AS cliente, oc.moneda,
       f.tipo_cambio_aplicado,
       SUM(fd.cantidad * fd.precio_unitario) AS total_moneda,
       SUM(fd.cantidad * fd.precio_unitario) * f.tipo_cambio_aplicado AS total_crc,
       SUM(fd.cantidad * fd.costo_unitario_crc) AS costo_crc,
       SUM(fd.cantidad * fd.precio_unitario) * f.tipo_cambio_aplicado
         - SUM(fd.cantidad * fd.costo_unitario_crc) AS margen_crc
FROM operacional.factura f
JOIN operacional.orden_compra oc ON oc.id_oc = f.id_oc
JOIN operacional.cliente cl ON cl.id_cliente = oc.id_cliente
JOIN operacional.factura_detalle fd ON fd.id_factura = f.id_factura
GROUP BY f.id_factura, f.numero_factura, f.fecha_factura,
         oc.numero_oc, cl.nombre, oc.moneda, f.tipo_cambio_aplicado;

-- Simulador "qué pasa si el dólar baja a X"
CREATE OR REPLACE FUNCTION operacional.simular_margen(
    p_id_producto INT, p_precio_usd NUMERIC, p_tc NUMERIC
) RETURNS TABLE (
    costo_crc NUMERIC, ingreso_crc NUMERIC, margen_crc NUMERIC, margen_pct NUMERIC
) AS $$
    SELECT x.c, p_precio_usd * p_tc, p_precio_usd * p_tc - x.c,
           ROUND((p_precio_usd * p_tc - x.c) / NULLIF(p_precio_usd * p_tc, 0), 4)
    FROM (SELECT operacional.costo_producto(p_id_producto, CURRENT_DATE) AS c) x;
$$ LANGUAGE sql STABLE;