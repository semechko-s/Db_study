-- Автоматические проверки восьми аналитических запросов.
-- Запускать в отдельной тестовой БД после:
--   test_data.sql
--   query_test_data.sql
-- и успешного выполнения queries/business_queries.sql.
-- Все проверки только читают данные.

CREATE TEMP TABLE query_test_results (
    id SERIAL PRIMARY KEY,
    test_name TEXT NOT NULL,
    passed BOOLEAN NOT NULL,
    details TEXT NOT NULL
);

-- 1. Просмотр заявок по статусу: должен находиться тестовый запрос в ремонте.
INSERT INTO query_test_results(test_name, passed, details)
SELECT
    '01: просмотр заявок',
    COUNT(*) > 0,
    'Найдено заявок: ' || COUNT(*)::text
FROM request r
JOIN equipment e ON e.id = r.equipment_id
JOIN client c ON c.id = e.client_id
LEFT JOIN employee op ON op.id = r.operator_id
WHERE r.status = 'В ремонте';

-- 2. Контроль ремонтных работ: есть выполняющийся ремонт с мастером.
INSERT INTO query_test_results(test_name, passed, details)
SELECT
    '02: контроль ремонтных работ',
    COUNT(*) > 0,
    'Найдено выполняющихся ремонтов: ' || COUNT(*)::text
FROM request r
JOIN work w ON w.request_id = r.id
JOIN repair rp ON rp.work_id = w.id
JOIN employee m ON m.id = rp.master_id
WHERE rp.status = 'Выполняется';

-- 3. Контроль активных резервов запчастей.
INSERT INTO query_test_results(test_name, passed, details)
SELECT
    '03: активные резервы запчастей',
    COUNT(*) > 0,
    'Найдено активных резервов: ' || COUNT(*)::text
FROM part_reservation pr
JOIN part p ON p.id = pr.part_id
JOIN repair rp ON rp.id = pr.repair_id
JOIN work w ON w.id = rp.work_id
JOIN request r ON r.id = w.request_id
WHERE pr.status = 'Активен';

-- 4. Агрегация количества заявок по клиентам.
INSERT INTO query_test_results(test_name, passed, details)
SELECT
    '04: агрегат по клиентам',
    COUNT(*) >= 2 AND COALESCE(SUM(request_count), 0) >= 2,
    'Клиентов в результате: ' || COUNT(*)::text ||
    ', заявок: ' || COALESCE(SUM(request_count), 0)::text
FROM (
    SELECT c.id, COUNT(r.id) AS request_count
    FROM client c
    LEFT JOIN equipment e ON e.client_id = c.id
    LEFT JOIN request r ON r.equipment_id = e.id
    GROUP BY c.id
) client_stats;

-- 5. Поиск клиентов с крупными расходами (порог каталога — 50000).
INSERT INTO query_test_results(test_name, passed, details)
SELECT
    '05: клиенты с крупными расходами',
    COUNT(*) > 0,
    'Клиентов выше порога: ' || COUNT(*)::text
FROM (
    SELECT c.id, SUM(p.amount) AS total_paid
    FROM client c
    JOIN equipment e ON e.client_id = c.id
    JOIN request r ON r.equipment_id = e.id
    JOIN payment p ON p.request_id = r.id
    WHERE p.status = 'Оплачено'
    GROUP BY c.id
    HAVING SUM(p.amount) >= 50000.00
) spending;

-- 6. Рейтинг мастеров по завершённым ремонтам.
INSERT INTO query_test_results(test_name, passed, details)
SELECT
    '06: рейтинг мастеров',
    COUNT(*) > 0 AND MIN(master_rank) = 1,
    'Мастеров в рейтинге: ' || COUNT(*)::text
FROM (
    SELECT
        m.id,
        RANK() OVER (ORDER BY COUNT(*) DESC, SUM(rp.cost) DESC) AS master_rank
    FROM repair rp
    JOIN employee m ON m.id = rp.master_id
    JOIN work w ON w.id = rp.work_id
    JOIN request r ON r.id = w.request_id
    WHERE rp.status = 'Завершён'
    GROUP BY m.id
) ranked_masters;

-- 7. Помесячная динамика оплат: LAG и накопительный итог.
INSERT INTO query_test_results(test_name, passed, details)
SELECT
    '07: динамика оплат, LAG и накопительный итог',
    COUNT(*) >= 2
        AND COUNT(previous_month_revenue) >= 1
        AND MAX(cumulative_revenue) > 0,
    'Месяцев: ' || COUNT(*)::text ||
    ', предыдущих значений: ' || COUNT(previous_month_revenue)::text
FROM (
    SELECT
        month,
        LAG(revenue) OVER (ORDER BY month) AS previous_month_revenue,
        SUM(revenue) OVER (
            ORDER BY month
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS cumulative_revenue
    FROM (
        SELECT date_trunc('month', paid_at)::date AS month, SUM(amount) AS revenue
        FROM payment
        WHERE status = 'Оплачено' AND paid_at IS NOT NULL
        GROUP BY date_trunc('month', paid_at)::date
    ) monthly
) payment_windows;

-- 8. История статусов: LEAD должен находить следующее событие.
INSERT INTO query_test_results(test_name, passed, details)
SELECT
    '08: длительность статусов, LEAD',
    COUNT(*) > 0 AND COUNT(next_changed_at) > 0,
    'Переходов с последующим событием: ' || COUNT(next_changed_at)::text
FROM (
    SELECT
        changed_at,
        LEAD(changed_at) OVER (
            PARTITION BY request_id
            ORDER BY changed_at, id
        ) AS next_changed_at
    FROM status_history
) status_events;

SELECT
    test_name AS "Проверка",
    CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS "Результат",
    details AS "Подробности"
FROM query_test_results
ORDER BY id;

DO $$
DECLARE
    total_count INTEGER;
    failed_count INTEGER;
BEGIN
    SELECT COUNT(*), COUNT(*) FILTER (WHERE NOT passed)
    INTO total_count, failed_count
    FROM query_test_results;

    RAISE NOTICE 'Проверок аналитических запросов: %, ошибок: %',
        total_count, failed_count;

    IF failed_count > 0 THEN
        RAISE EXCEPTION 'Не все проверки аналитических запросов пройдены';
    END IF;
END $$;
