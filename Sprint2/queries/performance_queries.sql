-- Запрос 1. Подсчёт активных резервов одной запчасти.
EXPLAIN (ANALYZE, BUFFERS)
SELECT COALESCE(SUM(pr.quantity), 0) AS reserved_quantity
FROM part_reservation pr
JOIN part p ON p.id = pr.part_id
WHERE p.article = 'BR09-CONCURRENCY-TEST'
  AND pr.status = 'Активен';

-- Запрос 2. Отчёт по активным резервам.
EXPLAIN (ANALYZE, BUFFERS)
SELECT
    pr.id AS reservation_id,
    p.name AS part_name,
    pr.quantity,
    pr.status,
    rp.id AS repair_id,
    r.id AS request_id
FROM part_reservation pr
JOIN part p ON p.id = pr.part_id
JOIN repair rp ON rp.id = pr.repair_id
JOIN work w ON w.id = rp.work_id
JOIN request r ON r.id = w.request_id
WHERE pr.status = 'Активен'
ORDER BY pr.reserved_at DESC;