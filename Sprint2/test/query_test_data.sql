-- Дополнительные детерминированные данные для проверок рейтинга,
-- порога расходов и помесячной динамики.
-- Запускать только в отдельной тестовой БД после test_data.sql.

-- 4500 рублей ниже порога 5000: клиент не должен попасть в запрос №5.
-- Платёж за февраль нужен для проверки LAG и накопительного итога.
INSERT INTO payment (request_id, amount, paid_at, method, status)
VALUES (
    2,
    4500.00,
    TIMESTAMP '2026-02-15 12:00:00',
    'Карта',
    'Оплачено'
);

INSERT INTO work (request_id, started_at, ended_at, status, cost)
VALUES (
    2,
    TIMESTAMP '2026-01-12 10:00:00',
    TIMESTAMP '2026-01-13 11:00:00',
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
    TIMESTAMP '2026-01-12 10:15:00',
    TIMESTAMP '2026-01-13 10:30:00',
    'Завершён'
FROM work w
CROSS JOIN employee e
WHERE w.request_id = 2
  AND e.specialization = 'Мастер'
ORDER BY e.id
LIMIT 1;
