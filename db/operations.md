# Operaciones sobre la base de datos `transportes`

Conexión: `psql -U postgres -d transportes`

## Estado actual

```
SELECT 'trabajador' AS tabla, count(*) FROM trabajador
UNION ALL SELECT 'nomina', count(*) FROM nomina
UNION ALL SELECT 'peticion', count(*) FROM peticion
UNION ALL SELECT 'factura', count(*) FROM factura;
```

## 1. Trabajador

Crear:
```
INSERT INTO trabajador (nombre, documento, cargo, telefono, email)
VALUES ('Ana Torres', '12312312', 'Chofer', '3100000001', 'ana@x.com')
RETURNING id, nombre;
```

Leer todos:
```
SELECT * FROM trabajador ORDER BY nombre;
```

Buscar por documento:
```
SELECT * FROM trabajador WHERE documento = '12345678';
```

Desactivar (no borrar):
```
UPDATE trabajador SET activo = FALSE WHERE id = 1;
```

Borrar (cascadea nóminas):
```
DELETE FROM trabajador WHERE id = 1;
```

## 2. Nómina

Crear:
```
INSERT INTO nomina (trabajador_id, periodo, monto, fecha_pago, estado)
VALUES (1, '2026-10', 2500000.00, '2026-10-25', 'pendiente')
RETURNING id, trabajador_id, periodo, monto, estado;
```

Ver nómina de un trabajador:
```
SELECT n.id, t.nombre, n.periodo, n.monto, n.fecha_pago, n.estado
FROM nomina n JOIN trabajador t ON t.id = n.trabajador_id
WHERE t.id = 1 ORDER BY n.periodo DESC;
```

Marcar pagada:
```
UPDATE nomina SET estado = 'pagada', fecha_pago = CURRENT_DATE WHERE id = 1;
```

Ver total por periodo:
```
SELECT periodo, sum(monto) AS total, count(*) AS trabajadores
FROM nomina WHERE estado = 'pagada'
GROUP BY periodo ORDER BY periodo;
```

## 3. Petición

Crear (desde trabajador):
```
INSERT INTO peticion (solicitante_nombre, solicitante_tipo, solicitante_id,
                      descripcion, monto_solicitado, estado)
VALUES ('Repuesto', 'trabajador', 1, 'Rueda unidad #UT-011', 450000.00, 'pendiente')
RETURNING id, solicitante_nombre, descripcion, estado;
```

Crear (desde cliente externo):
```
INSERT INTO peticion (solicitante_nombre, solicitante_tipo,
                      descripcion, monto_solicitado, estado)
VALUES ('Cliente Comercial', 'cliente', 'Carga palets sur', 2000000.00, 'aprobada')
RETURNING id, solicitante_nombre, estado;
```

Ver pendientes / aprobadas:
```
SELECT id, solicitante_nombre, descripcion, monto_solicitado, estado
FROM peticion WHERE estado IN ('pendiente','aprobada')
ORDER BY fecha_peticion DESC;
```

Aprobar:
```
UPDATE peticion SET estado = 'aprobada' WHERE id = 4;
```

Facturar:
```
UPDATE peticion SET estado = 'facturada' WHERE id = 4;
```

## 4. Factura

Crear (ligada a petición):
```
INSERT INTO factura (peticion_id, numero_factura, monto, fecha_vencimiento, estado)
VALUES (1, 'FAC-2026-0003', 3200000.00, CURRENT_DATE + INTERVAL '30 days', 'pendiente')
RETURNING id, numero_factura, peticion_id, monto, estado;
```

Crear (sin ligar):
```
INSERT INTO factura (numero_factura, monto, fecha_vencimiento, estado)
VALUES ('FAC-2026-0004', 800000.00, CURRENT_DATE + INTERVAL '15 days', 'pendiente')
RETURNING id, numero_factura, monto, estado;
```

Ver vencidas sin pagar:
```
SELECT f.id, f.numero_factura, f.monto, f.fecha_vencimiento, p.descripcion
FROM factura f LEFT JOIN peticion p ON p.id = f.peticion_id
WHERE f.fecha_vencimiento < CURRENT_DATE AND f.estado <> 'pagada'
ORDER BY f.fecha_vencimiento;
```

Pagar:
```
UPDATE factura SET estado = 'pagada' WHERE id = 1;
```

Ver total por estado:
```
SELECT estado, count(*) AS cant, sum(monto) AS total
FROM factura GROUP BY estado ORDER BY estado;
```

## 5. Reporte cruzado (el que ya está en SQL)

```
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
```

## 6. Transacciones (para actualizaciones en bloque seguro)

Ejemplo: crear factura + cambiar estado de petición a la vez seguro:
```
BEGIN;
  INSERT INTO factura (peticion_id, numero_factura, monto, fecha_vencimiento, estado)
  VALUES (4, 'FAC-2026-0005', 2000000.00, CURRENT_DATE + INTERVAL '30 days', 'pendiente');
  UPDATE peticion SET estado = 'facturada' WHERE id = 4;
COMMIT;
```
Si falla algo, el `COMMIT` no se ejecuta y todo se deshace solo.

## 7. Limpiar y recrear de cero

```
psql -U postgres -d transportes -c "DROP TABLE IF EXISTS factura, peticion, nomina, trabajador CASCADE;"
psql -U postgres -d transportes -f /home/wurst/setup_transporte.sql
```

## 8. Backup rápido

```
pg_dump -U postgres -d transportes -F c -f transportes.backup
```
Restaurar en otra base:
```
psql -U postgres -c "CREATE DATABASE transportes_test;"
pg_restore -U postgres -d transportes_test transportes.backup
```

## 9. Cosas que probablemente necesites después

- Tabla `clientes` externo si los clientes se repiten y querés tenerlos registrados
- Tabla `unidades` / vehículos si el transporte lleva registro de qué unidad hace qué
- Tabla `pagos` o `registro_caja` para no solo actualizar estado
- Tabla `asistencia` / `horas` si la nómina viene de cálculo real
- Tabla `usuario` / `sesion` si el software tiene login de varios empleados
