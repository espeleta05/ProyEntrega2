-- Cambia el unique constraint de lot_number (global) a (lot_number, clinic_id)
-- para permitir que el mismo número de lote exista en distintas clínicas
-- tras una transferencia parcial de stock.

-- 1. Eliminar constraint global
ALTER TABLE vaccine_lots
DROP CONSTRAINT IF EXISTS vaccine_lots_lot_number_key;

-- 2. Crear constraint por clínica
ALTER TABLE vaccine_lots
ADD CONSTRAINT vaccine_lots_lot_number_clinic_key
    UNIQUE (lot_number, clinic_id);
