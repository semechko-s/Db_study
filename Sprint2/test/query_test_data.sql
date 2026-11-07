-- Дополнительные данные для проверки всех восьми аналитических запросов.
-- Запускать только в отдельной тестовой БД после test_data.sql.
-- Скрипт не предназначен для рабочей базы.

INSERT INTO payment (request_id, amount, paid_at, method, status)
VALUES (
    2,
    55000.00,
    date_trunc('month', CURRENT_TIMESTAMP) - INTERVAL '1 month',
    'Карта',
    'Оплачено'
);

INSERT INTO work (request_id, started_at, ended_at, status, cost)
VALUES (
    2,
    CURRENT_TIMESTAMP - INTERVAL '10 days',
    CURRENT_TIMESTAMP - INTERVAL '9 days',
    'Завершена',
    3200.00
);

INSERT INTO repair (
    work_id, master_id, description, cost, result,
    started_at, ended_at, status
)
SELECT
    w.id,
    e.id,
    'Диагностика и замена аккумулятора',
    3200.00,
    'Аккумулятор заменён, устройство проверено',
    CURRENT_TIMESTAMP - INTERVAL '10 days',
    CURRENT_TIMESTAMP - INTERVAL '9 days',
    'Завершён'
FROM work w
CROSS JOIN employee e
WHERE w.request_id = 2
  AND e.specialization = 'Мастер'
ORDER BY e.id
LIMIT 1;
