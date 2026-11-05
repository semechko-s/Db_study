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

-- Рейтинг мастеров по завершённым ремонтам
WITH master_stats AS (
    SELECT
        m.id AS master_id,
        m.full_name AS master_name,
        COUNT(*) AS completed_repairs,
        COUNT(DISTINCT r.id) AS request_count,
        ROUND(SUM(rp.cost), 2) AS total_repair_cost,
        ROUND(AVG(rp.cost), 2) AS avg_repair_cost
    FROM repair rp
    JOIN employee m
        ON m.id = rp.master_id
    JOIN work w
        ON w.id = rp.work_id
    JOIN request r
        ON r.id = w.request_id
    WHERE rp.status = 'Завершён'
    GROUP BY
        m.id,
        m.full_name
)
SELECT
    master_id,
    master_name,
    completed_repairs,
    request_count,
    total_repair_cost,
    avg_repair_cost,
    RANK() OVER (
        ORDER BY completed_repairs DESC, total_repair_cost DESC
    ) AS master_rank,
    ROUND(
        100.0 * total_repair_cost / SUM(total_repair_cost) OVER (),
        2
    ) AS revenue_share_percent
FROM master_stats
ORDER BY master_rank, master_name;

-- Помесячная динамика оплат: LAG, накопительный итог и скользящее среднее
WITH monthly_payments AS (
    SELECT
        date_trunc('month', p.paid_at)::date AS month,
        COUNT(*) AS payment_count,
        COUNT(DISTINCT r.id) AS request_count,
        SUM(p.amount) AS revenue
    FROM payment p
    JOIN request r
        ON r.id = p.request_id
    WHERE p.status = 'Оплачено'
      AND p.paid_at IS NOT NULL
    GROUP BY
        date_trunc('month', p.paid_at)::date
),
revenue_with_lag AS (
    SELECT
        month,
        payment_count,
        request_count,
        revenue,
        LAG(revenue) OVER (ORDER BY month) AS previous_month_revenue
    FROM monthly_payments
)
SELECT
    month,
    payment_count,
    request_count,
    revenue,
    previous_month_revenue,
    ROUND(revenue - previous_month_revenue, 2) AS revenue_change,
    ROUND(
        100.0 * (revenue - previous_month_revenue)
        / NULLIF(previous_month_revenue, 0),
        2
    ) AS growth_percent,
    SUM(revenue) OVER (
        ORDER BY month
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_revenue,
    ROUND(
        AVG(revenue) OVER (
            ORDER BY month
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ),
        2
    ) AS moving_avg_3_months,
    RANK() OVER (ORDER BY revenue DESC) AS revenue_rank
FROM revenue_with_lag
ORDER BY month;

-- Анализ длительности статусов заявки: LEAD и нумерация шагов
WITH status_events AS (
    SELECT
        sh.id,
        sh.request_id,
        sh.changed_at,
        sh.old_status,
        sh.new_status,
        LEAD(sh.changed_at) OVER (
            PARTITION BY sh.request_id
            ORDER BY sh.changed_at, sh.id
        ) AS next_changed_at,
        LEAD(sh.new_status) OVER (
            PARTITION BY sh.request_id
            ORDER BY sh.changed_at, sh.id
        ) AS next_status,
        ROW_NUMBER() OVER (
            PARTITION BY sh.request_id
            ORDER BY sh.changed_at, sh.id
        ) AS step_number,
        COUNT(*) OVER (
            PARTITION BY sh.request_id
        ) AS total_steps
    FROM status_history sh
)
SELECT
    se.request_id,
    c.full_name AS client_name,
    e.manufacturer,
    e.model,
    se.step_number,
    se.total_steps,
    se.old_status,
    se.new_status AS status,
    se.changed_at,
    se.next_status,
    se.next_changed_at,
    ROUND(
        EXTRACT(EPOCH FROM (se.next_changed_at - se.changed_at)) / 3600.0,
        2
    ) AS hours_in_status
FROM status_events se
JOIN request r
    ON r.id = se.request_id
JOIN equipment e
    ON e.id = r.equipment_id
JOIN client c
    ON c.id = e.client_id
WHERE se.next_changed_at IS NOT NULL
ORDER BY se.request_id, se.step_number;
