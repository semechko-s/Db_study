BEGIN;

DROP TRIGGER IF EXISTS trg_check_part_reservation_stock
ON part_reservation;

DROP FUNCTION IF EXISTS check_part_reservation_stock();

DROP INDEX IF EXISTS idx_part_reservation_active_part;

COMMIT;
