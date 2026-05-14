-- ============================================================
-- Migración: columna is_active en vaccine_lots
-- Ejecutar UNA sola vez contra la BD.
-- ============================================================

BEGIN;

-- 1. Agregar columna (no-op si ya existe)
ALTER TABLE vaccine_lots
    ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;

-- 2. Marcar automáticamente como inactivos los lotes ya vencidos
UPDATE vaccine_lots
SET    is_active = FALSE
WHERE  expiration_date < NOW()::DATE
  AND  is_active = TRUE;

COMMIT;
