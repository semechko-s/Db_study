BEGIN;

-- Ускоряет поиск запчасти по артикулу.
CREATE INDEX idx_part_article
ON part(article);

-- Помогает получать активные резервы в нужном порядке.
CREATE INDEX idx_part_reservation_active_reserved_at
ON part_reservation(reserved_at DESC)
INCLUDE (part_id, repair_id, quantity)
WHERE status = 'Активен';

COMMIT;