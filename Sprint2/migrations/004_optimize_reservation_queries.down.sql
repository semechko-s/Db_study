BEGIN;

DROP INDEX IF EXISTS idx_part_reservation_active_reserved_at;
DROP INDEX IF EXISTS idx_part_article;

COMMIT;
