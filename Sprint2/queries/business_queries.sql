-- Просмотр заявок сервисного центра
PREPARE get_requests (text) AS
SELECT
    r.id AS request_id,
    c.full_name AS client_name,
    c.phone AS client_phone,
    e.type AS equipment_type,
    e.manufacturer,
    e.model,
    r.description,
    r.status AS request_status,
    r.created_at,
    r.preliminary_cost,
    op.full_name AS operator_name
FROM request r
JOIN equipment e ON e.id = r.equipment_id
JOIN client c ON c.id = e.client_id
LEFT JOIN employee op ON op.id = r.operator_id
WHERE r.status = $1
ORDER BY r.created_at DESC;

EXECUTE get_requests('В ремонте');

-- Контроль выполнения ремонтных работ
PREPARE get_works (text) AS
SELECT
    r.id AS request_id,
    c.full_name AS client_name,
    e.manufacturer,
    e.model,
    w.id AS work_id,
    w.status AS work_status,
    w.cost AS work_cost,
    rp.id AS repair_id,
    rp.description AS repair_description,
    rp.status AS repair_status,
    rp.cost AS repair_cost,
    m.full_name AS master_name
FROM request r
JOIN equipment e
    ON e.id = r.equipment_id
JOIN client c
    ON c.id = e.client_id
JOIN work w
    ON w.request_id = r.id
JOIN repair rp
    ON rp.work_id = w.id
JOIN employee m
    ON m.id = rp.master_id
WHERE rp.status = $1
ORDER BY r.id, w.id, rp.id;

EXECUTE get_works('Выполняяется');

-- Контроль зарезервированных запчастей
PREPARE get_parts (text) AS
SELECT
    pr.id AS reservation_id,
    p.name AS part_name,
    p.article,
    pr.quantity AS reserved_quantity,
    p.price AS part_price,
    pr.status AS reservation_status,
    rp.description AS repair_description,
    r.id AS request_id,
    c.full_name AS client_name,
    e.manufacturer,
    e.model
FROM part_reservation pr
JOIN part p
    ON p.id = pr.part_id
JOIN repair rp
    ON rp.id = pr.repair_id
JOIN work w
    ON w.id = rp.work_id
JOIN request r
    ON r.id = w.request_id
JOIN equipment e
    ON e.id = r.equipment_id
JOIN client c
    ON c.id = e.client_id
WHERE pr.status = $1
ORDER BY pr.reserved_at DESC;

EXECUTE get_parts('Активен');

-- Анализ количества заявок по клиентам
SELECT
    c.id AS client_id,
    c.full_name AS client_name,
    COUNT(r.id) AS request_count,
    COALESCE(SUM(r.preliminary_cost), 0) AS total_preliminary_cost
FROM client c
LEFT JOIN equipment e
    ON e.client_id = c.id
LEFT JOIN request r
    ON r.equipment_id = e.id
GROUP BY
    c.id,
    c.full_name
ORDER BY request_count DESC, c.full_name;

-- Поиск клиентов с крупными расходами на ремонт
PREPARE get_sum (decimal) AS
SELECT
    c.id AS client_id,
    c.full_name AS client_name,
    COUNT(p.id) AS payment_count,
    SUM(p.amount) AS total_paid
FROM client c
JOIN equipment e
    ON e.client_id = c.id
JOIN request r
    ON r.equipment_id = e.id
JOIN payment p
    ON p.request_id = r.id
WHERE p.status = 'Оплачено'
GROUP BY
    c.id,
    c.full_name
HAVING SUM(p.amount) >= $1
ORDER BY total_paid DESC;

EXECUTE get_sum(50000.00);