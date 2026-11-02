-- ===================== OPERACIONAL =====================

CREATE TABLE operacional.sector (
    id_sector SERIAL PRIMARY KEY,
    nombre VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE operacional.cliente (
    id_cliente SERIAL PRIMARY KEY,
    nombre VARCHAR(120) NOT NULL UNIQUE,
    id_sector INT NOT NULL
        REFERENCES operacional.sector(id_sector) ON DELETE RESTRICT,
    tipo_cliente VARCHAR(10) NOT NULL,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT ck_cliente_tipo
        CHECK (tipo_cliente IN ('Interno', 'Externo'))
);

CREATE TABLE operacional.material (
    id_material SERIAL PRIMARY KEY,
    nombre VARCHAR(30) NOT NULL UNIQUE
);

CREATE TABLE operacional.producto (
    id_producto SERIAL PRIMARY KEY,
    codigo VARCHAR(30) NOT NULL,
    descripcion VARCHAR(150) NOT NULL,
    tipo_producto VARCHAR(20) NOT NULL,
    id_material INT NOT NULL
        REFERENCES operacional.material(id_material) ON DELETE RESTRICT,
    largo_mm INT,
    ancho_mm INT,
    alto_mm INT,
    test INT,
    activo BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_producto_codigo UNIQUE (codigo),
    CONSTRAINT ck_producto_tipo
        CHECK (tipo_producto IN ('Caja corrugada', 'Caja Duplex', 'Separador')),
    CONSTRAINT ck_producto_medidas
        CHECK (
            COALESCE(largo_mm, 1) > 0
            AND COALESCE(ancho_mm, 1) > 0
            AND COALESCE(alto_mm, 1) > 0
            AND COALESCE(test, 1) > 0
        )
);

CREATE TABLE operacional.insumo (
    id_insumo SERIAL PRIMARY KEY,
    nombre VARCHAR(80) NOT NULL UNIQUE,
    unidad VARCHAR(15) NOT NULL
);

CREATE TABLE operacional.costo_insumo (
    id_costo SERIAL PRIMARY KEY,
    id_insumo INT NOT NULL
        REFERENCES operacional.insumo(id_insumo) ON DELETE RESTRICT,
    fecha_vigencia DATE NOT NULL,
    costo_unitario_crc NUMERIC(14,4) NOT NULL,
    CONSTRAINT uq_costo_insumo_fecha
        UNIQUE (id_insumo, fecha_vigencia),
    CONSTRAINT ck_costo_positivo
        CHECK (costo_unitario_crc > 0)
);

CREATE TABLE operacional.producto_insumo (
    id_producto INT NOT NULL
        REFERENCES operacional.producto(id_producto) ON DELETE CASCADE,
    id_insumo INT NOT NULL
        REFERENCES operacional.insumo(id_insumo) ON DELETE RESTRICT,
    cantidad_por_unidad NUMERIC(12,4) NOT NULL,
    PRIMARY KEY (id_producto, id_insumo),
    CONSTRAINT ck_receta_cantidad
        CHECK (cantidad_por_unidad > 0)
);

CREATE TABLE operacional.tipo_cambio (
    fecha DATE PRIMARY KEY,
    compra NUMERIC(8,2) NOT NULL,
    venta NUMERIC(8,2) NOT NULL,
    CONSTRAINT ck_tc_compra_positiva CHECK (compra > 0),
    CONSTRAINT ck_tc_venta_mayor_compra CHECK (venta >= compra)
);

CREATE TABLE operacional.orden_compra (
    id_oc SERIAL PRIMARY KEY,
    numero_oc VARCHAR(30) NOT NULL,
    id_cliente INT NOT NULL
        REFERENCES operacional.cliente(id_cliente) ON DELETE RESTRICT,
    fecha_oc DATE NOT NULL DEFAULT CURRENT_DATE,
    fecha_entrega DATE NOT NULL,
    moneda CHAR(3) NOT NULL,
    estado VARCHAR(20) NOT NULL DEFAULT 'Pendiente',
    CONSTRAINT uq_oc_numero UNIQUE (numero_oc),
    CONSTRAINT ck_oc_moneda CHECK (moneda IN ('CRC', 'USD')),
    CONSTRAINT ck_oc_estado
        CHECK (estado IN ('Pendiente', 'En producción', 'Facturada', 'Anulada')),
    CONSTRAINT ck_oc_fechas CHECK (fecha_entrega >= fecha_oc)
);

CREATE TABLE operacional.oc_detalle (
    id_detalle SERIAL PRIMARY KEY,
    id_oc INT NOT NULL
        REFERENCES operacional.orden_compra(id_oc) ON DELETE CASCADE,
    id_producto INT NOT NULL
        REFERENCES operacional.producto(id_producto) ON DELETE RESTRICT,
    cantidad INT NOT NULL,
    precio_unitario NUMERIC(14,4) NOT NULL,
    CONSTRAINT uq_oc_producto UNIQUE (id_oc, id_producto),
    CONSTRAINT ck_ocd_cantidad CHECK (cantidad > 0),
    CONSTRAINT ck_ocd_precio CHECK (precio_unitario > 0)
);

CREATE TABLE operacional.factura (
    id_factura SERIAL PRIMARY KEY,
    numero_factura VARCHAR(30) NOT NULL,
    id_oc INT NOT NULL
        REFERENCES operacional.orden_compra(id_oc) ON DELETE RESTRICT,
    fecha_factura DATE NOT NULL DEFAULT CURRENT_DATE,
    tipo_cambio_aplicado NUMERIC(8,2) NOT NULL DEFAULT 1,
    CONSTRAINT uq_factura_numero UNIQUE (numero_factura),
    CONSTRAINT uq_factura_oc UNIQUE (id_oc),
    CONSTRAINT ck_factura_tc CHECK (tipo_cambio_aplicado > 0)
);

CREATE TABLE operacional.factura_detalle (
    id_detalle SERIAL PRIMARY KEY,
    id_factura INT NOT NULL
        REFERENCES operacional.factura(id_factura) ON DELETE CASCADE,
    id_producto INT NOT NULL
        REFERENCES operacional.producto(id_producto) ON DELETE RESTRICT,
    cantidad INT NOT NULL,
    precio_unitario NUMERIC(14,4) NOT NULL,
    costo_unitario_crc NUMERIC(14,4) NOT NULL,
    CONSTRAINT uq_factura_producto UNIQUE (id_factura, id_producto),
    CONSTRAINT ck_fd_cantidad CHECK (cantidad > 0),
    CONSTRAINT ck_fd_precio CHECK (precio_unitario > 0)
);

-- ===================== ANALITICO =====================

CREATE TABLE analitico.stg_sector (LIKE operacional.sector);
CREATE TABLE analitico.stg_cliente (LIKE operacional.cliente);
CREATE TABLE analitico.stg_material (LIKE operacional.material);
CREATE TABLE analitico.stg_producto (LIKE operacional.producto);
CREATE TABLE analitico.stg_tipo_cambio (LIKE operacional.tipo_cambio);
CREATE TABLE analitico.stg_orden_compra (LIKE operacional.orden_compra);
CREATE TABLE analitico.stg_factura (LIKE operacional.factura);
CREATE TABLE analitico.stg_factura_detalle (LIKE operacional.factura_detalle);

CREATE TABLE analitico.dim_fecha (
    fecha DATE PRIMARY KEY,
    anio INT,
    mes INT,
    nombre_mes VARCHAR(15),
    trimestre INT,
    semana INT,
    anio_mes CHAR(7)
);

CREATE TABLE analitico.dim_producto (
    id_producto INT PRIMARY KEY,
    codigo VARCHAR(30),
    descripcion VARCHAR(150),
    tipo_producto VARCHAR(20),
    material VARCHAR(30),
    test INT
);

CREATE TABLE analitico.dim_cliente (
    id_cliente INT PRIMARY KEY,
    nombre VARCHAR(120),
    sector VARCHAR(50),
    tipo_cliente VARCHAR(10)
);

CREATE TABLE analitico.fact_ventas (
    id_detalle INT PRIMARY KEY,
    id_factura INT NOT NULL,
    fecha DATE NOT NULL,
    fecha_oc DATE NOT NULL,
    dias_oc_factura INT,
    id_producto INT NOT NULL,
    id_cliente INT NOT NULL,
    moneda CHAR(3) NOT NULL,
    cantidad INT NOT NULL,
    precio_unitario NUMERIC(14,4) NOT NULL,
    tc_factura NUMERIC(8,2) NOT NULL,
    tc_oc NUMERIC(8,2) NOT NULL,
    ingreso_crc NUMERIC(18,2),
    ingreso_crc_tc_oc NUMERIC(18,2),
    efecto_cambiario_crc NUMERIC(18,2),
    costo_crc NUMERIC(18,2),
    margen_crc NUMERIC(18,2),
    margen_pct NUMERIC(8,4)
);

CREATE TABLE analitico.parametro (
    nombre VARCHAR(50) PRIMARY KEY,
    valor NUMERIC(10,4) NOT NULL
);

INSERT INTO analitico.parametro (nombre, valor)
VALUES ('margen_objetivo', 0.20);

CREATE TABLE analitico.elt_log (
    id SERIAL PRIMARY KEY,
    ejecutado TIMESTAMP NOT NULL DEFAULT NOW(),
    filas_staging INT,
    filas_hechos INT
);