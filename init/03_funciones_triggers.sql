-- Costo en colones de un producto a una fecha (último costo vigente de cada insumo).
-- Devuelve NULL si no hay receta o si a algún insumo le falta costo a esa fecha.
CREATE OR REPLACE FUNCTION operacional.costo_producto(p_id INT, p_fecha DATE)
RETURNS NUMERIC AS $$
  SELECT CASE WHEN COUNT(*) = 0 OR COUNT(*) FILTER (WHERE c.costo IS NULL) > 0 THEN NULL
              ELSE SUM(pi.cantidad_por_unidad * c.costo) END
  FROM operacional.producto_insumo pi
  LEFT JOIN LATERAL (
    SELECT ci.costo_unitario_crc AS costo
    FROM operacional.costo_insumo ci
    WHERE ci.id_insumo = pi.id_insumo AND ci.fecha_vigencia <= p_fecha
    ORDER BY ci.fecha_vigencia DESC LIMIT 1
  ) c ON TRUE
  WHERE pi.id_producto = p_id;
$$ LANGUAGE sql STABLE;

-- FACTURA (antes de insertar): valida OC y fija el tipo de cambio
CREATE OR REPLACE FUNCTION operacional.trg_factura_antes() RETURNS trigger AS $$
DECLARE v_moneda CHAR(3); v_estado VARCHAR(20); v_tc NUMERIC;
BEGIN
  SELECT moneda, estado INTO v_moneda, v_estado
  FROM operacional.orden_compra WHERE id_oc = NEW.id_oc;

  IF v_estado = 'Anulada' THEN
    RAISE EXCEPTION 'No se puede facturar una OC anulada';
  END IF;

  IF v_moneda = 'USD' THEN
    SELECT compra INTO v_tc
    FROM operacional.tipo_cambio
    WHERE fecha <= NEW.fecha_factura AND fecha >= NEW.fecha_factura - 7
    ORDER BY fecha DESC LIMIT 1;
    IF v_tc IS NULL THEN
      RAISE EXCEPTION 'No hay tipo de cambio registrado (últimos 7 días) para la fecha %', NEW.fecha_factura;
    END IF;
    NEW.tipo_cambio_aplicado := v_tc;
  ELSE
    NEW.tipo_cambio_aplicado := 1;
  END IF;
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_factura_antes
BEFORE INSERT ON operacional.factura
FOR EACH ROW EXECUTE FUNCTION operacional.trg_factura_antes();

-- FACTURA (después): mantiene el estado de la OC
CREATE OR REPLACE FUNCTION operacional.trg_factura_despues() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE operacional.orden_compra SET estado = 'Facturada' WHERE id_oc = NEW.id_oc;
    RETURN NEW;
  ELSE
    UPDATE operacional.orden_compra SET estado = 'En producción' WHERE id_oc = OLD.id_oc;
    RETURN OLD;
  END IF;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_factura_despues
AFTER INSERT OR DELETE ON operacional.factura
FOR EACH ROW EXECUTE FUNCTION operacional.trg_factura_despues();

-- FACTURA_DETALLE: producto debe estar en la OC y el costo se congela
CREATE OR REPLACE FUNCTION operacional.trg_factura_detalle_antes() RETURNS trigger AS $$
DECLARE v_fecha DATE; v_oc INT; v_costo NUMERIC;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    NEW.costo_unitario_crc := OLD.costo_unitario_crc;   -- el costo congelado no se modifica
    RETURN NEW;
  END IF;

  SELECT fecha_factura, id_oc INTO v_fecha, v_oc
  FROM operacional.factura WHERE id_factura = NEW.id_factura;

  IF NOT EXISTS (SELECT 1 FROM operacional.oc_detalle d
                 WHERE d.id_oc = v_oc AND d.id_producto = NEW.id_producto) THEN
    RAISE EXCEPTION 'El producto no pertenece a la OC que se está facturando';
  END IF;

  v_costo := operacional.costo_producto(NEW.id_producto, v_fecha);
  IF v_costo IS NULL THEN
    RAISE EXCEPTION 'El producto no tiene receta o le faltan costos de insumos a la fecha %', v_fecha;
  END IF;
  NEW.costo_unitario_crc := v_costo;                    -- siempre se calcula, ignora lo enviado
  RETURN NEW;
END; $$ LANGUAGE plpgsql;

CREATE TRIGGER trg_factura_detalle_antes
BEFORE INSERT OR UPDATE ON operacional.factura_detalle
FOR EACH ROW EXECUTE FUNCTION operacional.trg_factura_detalle_antes();