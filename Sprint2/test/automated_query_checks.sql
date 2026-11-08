-- Проверки сравнивают результаты временных представлений,
-- созданных непосредственно в business_queries.sql.
-- Запускать в том же подключении psql сразу после business_queries.sql.

CREATE TEMP TABLE query_test_results (
    id INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    test_name TEXT NOT NULL,
    passed BOOLEAN NOT NULL,
    details TEXT NOT NULL
);

-- 1. Проверяем полный набор полей и точное содержимое заявки в ремонте.
WITH expected AS (
    SELECT
        1::bigint AS request_id,
        'Иванов Иван Иванович'::varchar(255) AS client_name,
        '+79990000001'::varchar(30) AS client_phone,
        'Ноутбук'::varchar(100) AS equipment_type,
        'Lenovo'::varchar(100) AS manufacturer,
        'ThinkPad T14'::varchar(100) AS model,
        'Ноутбук сильно нагревается'::text AS description,
        'В ремонте'::varchar(30) AS request_status,
        TIMESTAMP '2026-01-10 09:00:00' AS created_at,
        5500.00::numeric AS preliminary_cost,
        'Оператор Оля'::varchar(255) AS operator_name
)
INSERT INTO query_test_results(test_name, passed, details)
SELECT
    '01: просмотр заявок',
    NOT EXISTS (
        (SELECT * FROM query_01_requests EXCEPT ALL SELECT * FROM expected)
        UNION ALL
        (SELECT * FROM expected EXCEPT ALL SELECT * FROM query_01_requests)
    ),
    format('ожидалась ровно 1 заявка с id=1; получено строк: %s',
           (SELECT COUNT(*) FROM query_01_requests));

-- 2. Проверяем конкретную работу, ремонт, стоимость и назначенного мастера.
WITH expected AS (
    SELECT
        1::bigint AS request_id,
        'Иванов Иван Иванович'::varchar(255) AS client_name,
        'Lenovo'::varchar(100) AS manufacturer,
        'ThinkPad T14'::varchar(100) AS model,
        1::bigint AS work_id,
        'Выполняется'::varchar(30) AS work_status,
        5500.00::numeric AS work_cost,
        1::bigint AS repair_id,
        'Очистка системы охлаждения'::text AS repair_description,
        'Выполняется'::varchar(30) AS repair_status,
        1500.00::numeric AS repair_cost,
        'Мастер Миша'::varchar(255) AS master_name
)
INSERT INTO query_test_results(test_name, passed, details)
SELECT
    '02: контроль ремонтных работ',
    NOT EXISTS (
        (SELECT * FROM query_02_works EXCEPT ALL SELECT * FROM expected)
        UNION ALL
        (SELECT * FROM expected EXCEPT ALL SELECT * FROM query_02_works)
    ),
    format('ожидалась 1 выполняющаяся работа по заявке 1; получено строк: %s',
           (SELECT COUNT(*) FROM query_02_works));

-- 3. Проверяем конкретный резерв, запчасть, количество и заявку.
WITH expected AS (
    SELECT
        1::bigint AS reservation_id,
        'Термопаста Arctic MX-6'::varchar(255) AS part_name,
        'TP-MX6-001'::varchar(100) AS article,
        1::integer AS reserved_quantity,
        800.00::numeric AS part_price,
        'Активен'::varchar(30) AS reservation_status,
        'Очистка системы охлаждения'::text AS repair_description,
        1::bigint AS request_id,
        'Иванов Иван Иванович'::varchar(255) AS client_name,
        'Lenovo'::varchar(100) AS manufacturer,
        'ThinkPad T14'::varchar(100) AS model
)
INSERT INTO query_test_results(test_name, passed, details)
SELECT
    '03: активные резервы запчастей',
    NOT EXISTS (
        (SELECT * FROM query_03_parts EXCEPT ALL SELECT * FROM expected)
        UNION ALL
        (SELECT * FROM expected EXCEPT ALL SELECT * FROM query_03_parts)
    ),
    format('ожидался 1 активный резерв с id=1; получено строк: %s',
           (SELECT COUNT(*) FROM query_03_parts));

-- 4. Проверяем точное количество заявок и предварительную стоимость по каждому клиенту.
WITH expected AS (
    SELECT *
    FROM (VALUES
        (1::bigint, 'Иванов Иван Иванович'::varchar(255), 1::bigint, 5500.00::numeric),
        (2::bigint, 'Петрова Анна Сергеевна'::varchar(255), 1::bigint, 4500.00::numeric)
    ) AS values_table(client_id, client_name, request_count, total_preliminary_cost)
)
INSERT INTO query_test_results(test_name, passed, details)
SELECT
    '04: агрегат по клиентам',
    NOT EXISTS (
        (SELECT * FROM query_04_client_stats EXCEPT ALL SELECT * FROM expected)
        UNION ALL
        (SELECT * FROM expected EXCEPT ALL SELECT * FROM query_04_client_stats)
    ),
    format('ожидались 2 клиента и по 1 заявке у каждого; получено строк: %s',
           (SELECT COUNT(*) FROM query_04_client_stats));

-- 5. Порог каталога — 5000.00: платёж 5500 должен попасть в результат,
-- платёж 4500 должен быть исключён.
WITH expected AS (
    SELECT
        1::bigint AS client_id,
        'Иванов Иван Иванович'::varchar(255) AS client_name,
        1::bigint AS payment_count,
        5500.00::numeric AS total_paid
)
INSERT INTO query_test_results(test_name, passed, details)
SELECT
    '05: клиенты с крупными расходами',
    NOT EXISTS (
        (SELECT * FROM query_05_large_spending EXCEPT ALL SELECT * FROM expected)
        UNION ALL
        (SELECT * FROM expected EXCEPT ALL SELECT * FROM query_05_large_spending)
    ),
    format('при пороге 5000 ожидался только клиент 1 с суммой 5500; получено строк: %s',
           (SELECT COUNT(*) FROM query_05_large_spending));

-- 6. Проверяем все вычисленные показатели рейтинга мастеров.
WITH expected AS (
    SELECT
        2::bigint AS master_id,
        'Мастер Миша'::varchar(255) AS master_name,
        1::bigint AS completed_repairs,
        1::bigint AS request_count,
        3200.00::numeric AS total_repair_cost,
        3200.00::numeric AS avg_repair_cost,
        1::bigint AS master_rank,
        100.00::numeric AS revenue_share_percent
)
INSERT INTO query_test_results(test_name, passed, details)
SELECT
    '06: рейтинг мастеров',
    NOT EXISTS (
        (SELECT * FROM query_06_master_ranking EXCEPT ALL SELECT * FROM expected)
        UNION ALL
        (SELECT * FROM expected EXCEPT ALL SELECT * FROM query_06_master_ranking)
    ),
    format('ожидался 1 мастер с 1 завершённым ремонтом и рангом 1; получено строк: %s',
           (SELECT COUNT(*) FROM query_06_master_ranking));

-- 7. Проверяем помесячные суммы, LAG, разницу, рост, накопительный итог,
-- скользящее среднее и ранг.
WITH expected AS (
    SELECT *
    FROM (VALUES
        (
            DATE '2026-01-01',
            1::bigint,
            1::bigint,
            5500.00::numeric,
            NULL::numeric,
            NULL::numeric,
            NULL::numeric,
            5500.00::numeric,
            5500.00::numeric,
            1::bigint
        ),
        (
            DATE '2026-02-01',
            1::bigint,
            1::bigint,
            4500.00::numeric,
            5500.00::numeric,
            -1000.00::numeric,
            -18.18::numeric,
            10000.00::numeric,
            5000.00::numeric,
            2::bigint
        )
    ) AS values_table(
        month, payment_count, request_count, revenue,
        previous_month_revenue, revenue_change, growth_percent,
        cumulative_revenue, moving_avg_3_months, revenue_rank
    )
)
INSERT INTO query_test_results(test_name, passed, details)
SELECT
    '07: динамика оплат, LAG и накопительный итог',
    NOT EXISTS (
        (SELECT * FROM query_07_monthly_payments EXCEPT ALL SELECT * FROM expected)
        UNION ALL
        (SELECT * FROM expected EXCEPT ALL SELECT * FROM query_07_monthly_payments)
    ),
    format('ожидались январь и февраль 2026 с доходами 5500 и 4500; получено месяцев: %s',
           (SELECT COUNT(*) FROM query_07_monthly_payments));

-- 8. Проверяем конкретный переход статуса и длительность 2.5 часа.
WITH expected AS (
    SELECT
        1::bigint AS request_id,
        'Иванов Иван Иванович'::varchar(255) AS client_name,
        'Lenovo'::varchar(100) AS manufacturer,
        'ThinkPad T14'::varchar(100) AS model,
        1::bigint AS step_number,
        2::bigint AS total_steps,
        'Создана'::varchar(30) AS old_status,
        'Принята'::varchar(30) AS status,
        TIMESTAMP '2026-01-10 10:00:00' AS changed_at,
        'В ремонте'::varchar(30) AS next_status,
        TIMESTAMP '2026-01-10 12:30:00' AS next_changed_at,
        2.50::numeric AS hours_in_status
)
INSERT INTO query_test_results(test_name, passed, details)
SELECT
    '08: длительность статусов, LEAD',
    NOT EXISTS (
        (SELECT * FROM query_08_status_duration EXCEPT ALL SELECT * FROM expected)
        UNION ALL
        (SELECT * FROM expected EXCEPT ALL SELECT * FROM query_08_status_duration)
    ),
    format('ожидался 1 переход длительностью 2.50 часа; получено строк: %s',
           (SELECT COUNT(*) FROM query_08_status_duration));

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
