-- ============================================================
-- Base de datos: transportes
-- Empresa de transporte de personas y cosas (no animales)
-- 4 tablas: trabajador, nomina, peticion, factura
-- ============================================================

BEGIN;

-- 1. Trabajador: quien conduce / maneja las unidades
CREATE TABLE IF NOT EXISTS trabajador (
    id SERIAL PRIMARY KEY,
    nombre VARCHAR(100) NOT NULL,
    documento VARCHAR(50) UNIQUE NOT NULL,
    cargo VARCHAR(80),
    telefono VARCHAR(20),
    email VARCHAR(120),
    activo BOOLEAN DEFAULT TRUE,
    creado_en TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Nómina: registro de pago por periodo
CREATE TABLE IF NOT EXISTS nomina (
    id SERIAL PRIMARY KEY,
    trabajador_id INTEGER NOT NULL REFERENCES trabajador(id) ON DELETE CASCADE,
    periodo VARCHAR(20) NOT NULL,
    monto DECIMAL(12,2) NOT NULL CHECK (monto >= 0),
    fecha_pago DATE,
    estado VARCHAR(20) DEFAULT 'pendiente'
        CHECK (estado IN ('pendiente','pagada','anulada')),
    notas TEXT,
    creado_en TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Petición: alguien quiere comprar algo
CREATE TABLE IF NOT EXISTS peticion (
    id SERIAL PRIMARY KEY,
    solicitante_nombre VARCHAR(100) NOT NULL,
    solicitante_tipo VARCHAR(20)
        CHECK (solicitante_tipo IN ('trabajador','cliente')),
    solicitante_id INTEGER,             -- si es trabajador, id de trabajador
    descripcion TEXT NOT NULL,
    monto_solicitado DECIMAL(12,2) NOT NULL CHECK (monto_solicitado >= 0),
    fecha_peticion TIMESTAMPTZ DEFAULT NOW(),
    estado VARCHAR(20) DEFAULT 'pendiente'
        CHECK (estado IN ('pendiente','aprobada','rechazada','facturada')),
    observaciones TEXT
);

-- 4. Factura: documento por pagar
CREATE TABLE IF NOT EXISTS factura (
    id SERIAL PRIMARY KEY,
    peticion_id INTEGER REFERENCES peticion(id) ON DELETE SET NULL,
    numero_factura VARCHAR(30) UNIQUE,
    monto DECIMAL(12,2) NOT NULL CHECK (monto >= 0),
    fecha_emision DATE DEFAULT CURRENT_DATE,
    fecha_vencimiento DATE,
    estado VARCHAR(20) DEFAULT 'pendiente'
        CHECK (estado IN ('pendiente','pagada','vencida','anulada')),
    creado_en TIMESTAMPTZ DEFAULT NOW()
);

-- Índices para consultas comunes
CREATE INDEX IF NOT EXISTS idx_nomina_trabajador ON nomina(trabajador_id);
CREATE INDEX IF NOT EXISTS idx_peticion_estado ON peticion(estado);
CREATE INDEX IF NOT EXISTS idx_factura_peticion ON factura(peticion_id);

COMMIT;

-- ============================================================
-- DATOS DE PRUEBA
-- ============================================================

BEGIN;

-- Trabajadores
INSERT INTO trabajador (nombre, documento, cargo, telefono, email)
VALUES
  ('Juan Pérez',     '12345678', 'Chofer plataforma',    '3101234567', 'juan@empresa.co'),
  ('María Gómez',    '87654321', 'Chofer refrigerado',   '3109876543', 'maria@empresa.co'),
  ('Carlos Ruiz',    '11223344', 'Auxiliar logística',   '3155551234', 'carlos@empresa.co')
RETURNING id, nombre, documento;

-- Nóminas
INSERT INTO nomina (trabajador_id, periodo, monto, fecha_pago, estado)
VALUES
  (1, '2026-09', 2500000.00, '2026-09-25', 'pagada'),
  (2, '2026-09', 2800000.00, '2026-09-25', 'pagada'),
  (3, '2026-09', 1800000.00, '2026-09-26', 'pendiente')
RETURNING id, trabajador_id, periodo, monto, estado;

-- Peticiones
INSERT INTO peticion (solicitante_nombre, solicitante_tipo, solicitante_id,
                      descripcion, monto_solicitado, estado)
VALUES
  ('Compra de palets',     'cliente', NULL,           '500 palets madera terminal sur',     3200000.00, 'aprobada'),
  ('Repuesto motor',       'trabajador', 1,           'Alternador unidad #UT-042',           850000.00,  'pendiente'),
  ('Combustible extra',    'trabajador', 2,           'Reposición diésel Medellín-Bogotá',  1500000.00, 'facturada')
RETURNING id, solicitante_nombre, descripcion, monto_solicitado, estado;

-- Facturas
INSERT INTO factura (peticion_id, numero_factura, monto, fecha_emision,
                     fecha_vencimiento, estado)
VALUES
  (1, 'FAC-2026-0001', 3200000.00, '2026-09-20', '2026-10-20', 'pendiente'),
  (3, 'FAC-2026-0002', 1500000.00, '2026-09-22', '2026-10-22', 'pagada')
RETURNING id, peticion_id, numero_factura, monto, estado;

COMMIT;

-- ============================================================
-- CONSULTAS DE EJEMPLO
-- ============================================================

-- a) Ver todos los trabajadores
-- SELECT * FROM trabajador;

-- b) Nómina de un trabajador por periodo
-- SELECT t.nombre, n.periodo, n.monto, n.fecha_pago, n.estado
-- FROM nomina n JOIN trabajador t ON t.id = n.trabajador_id
-- WHERE t.nombre = 'Juan Pérez' AND n.periodo = '2026-09';

-- c) Peticiones aprobadas pendientes de factura
-- SELECT id, solicitante_nombre, descripcion, monto_solicitado, estado
-- FROM peticion WHERE estado = 'aprobada';

-- d) Facturas vencidas hoy o antes
-- SELECT f.numero_factura, f.monto, f.fecha_vencimiento, f.estado, p.descripcion
-- FROM factura f JOIN peticion p ON p.id = f.peticion_id
-- WHERE f.fecha_vencimiento <= CURRENT_DATE AND f.estado <> 'pagada';

-- e) Reporte completo: factura -> peticion -> trabajador -> nómina
SELECT
    f.id              AS factura_id,
    f.numero_factura,
    f.monto           AS monto_factura,
    f.estado          AS estado_factura,
    p.id              AS peticion_id,
    p.descripcion,
    p.monto_solicitado,
    p.estado          AS estado_peticion,
    t.nombre          AS trabajador_relacionado,
    n.periodo,
    n.monto           AS monto_nomina,
    n.estado          AS estado_nomina
FROM factura f
LEFT JOIN peticion p ON f.peticion_id = p.id
LEFT JOIN trabajador t ON t.id = p.solicitante_id
LEFT JOIN nomina n ON n.trabajador_id = t.id
ORDER BY f.id;

-- f) Total por estado de factura
-- SELECT estado, count(*) AS cant, sum(monto) AS total
-- FROM factura GROUP BY estado;

-- g) Peticiones sin factura asociada
-- SELECT p.id, p.descripcion, p.monto_solicitado, p.estado
-- FROM peticion p LEFT JOIN factura f ON f.peticion_id = p.id
-- WHERE f.id IS NULL;

-- h) Transacción: crear factura + cambiar estado de peticion a 'facturada'
-- BEGIN;
--   INSERT INTO factura (peticion_id, numero_factura, monto, fecha_vencimiento, estado)
--   VALUES (2, 'FAC-2026-0003', 850000.00, '2026-10-25', 'pendiente');
--   UPDATE peticion SET estado = 'facturada' WHERE id = 2;
-- COMMIT;

-- ============================================================
-- LIMPIEZA / BORRADO (solo si quieres empezar de cero)
-- ============================================================
-- DROP TABLE IF EXISTS factura, peticion, nomina, trabajador CASCADE;
