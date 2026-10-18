
-- ============================================================
-- Система сервисного центра — демонстрация транзакций
--
-- Часть 0. Подготовка данных с автоматической генерацией ID.
-- Часть 1. Успешное завершение ремонта и COMMIT.
-- Часть 2. Неудачная операция и полный ROLLBACK.
--
-- Существующие записи не удаляются.
-- Фиксированные значения первичных ключей не используются.
--
-- Запуск:
-- psql -d service_center -f scripts/transaction_demo.sql
-- ============================================================

\set ON_ERROR_STOP on

-- ============================================================
-- ЧАСТЬ 0. Подготовка данных
-- ============================================================

-- Создаём клиента.
INSERT INTO client (full_name, phone)
VALUES (
    'Петров Пётр Петрович',
    format('+7999%s', lpad(txid_current()::text, 7, '0'))
)
RETURNING id
\gset client_

-- Создаём устройство.
INSERT INTO equipment
    (client_id, type, manufacturer, model, status)
VALUES (
    :client_id,
    'Принтер',
    'HP',
    'LaserJet',
    'На ремонте'
)
RETURNING id
\gset equipment_

-- Создаём мастера.
INSERT INTO employee (full_name, specialization)
VALUES (
    'Мастер Сергей',
    'Мастер'
)
RETURNING id
\gset master_

-- Создаём запчасть с начальным остатком 2 штуки.
INSERT INTO part (name, article, price, stock_quantity)
VALUES (
    'Картридж',
    format('CART-%s', txid_current()),
    1200.00,
    2
)
RETURNING id
\gset part_

-- Создаём заявку.
INSERT INTO request
    (equipment_id, description, status, client_approved, approval_at)
VALUES (
    :equipment_id,
    'Не печатает',
    'В ремонте',
    true,
    now()
)
RETURNING id
\gset request_

-- Создаём работу.
INSERT INTO work (request_id, status, cost)
VALUES (
    :request_id,
    'Выполняется',
    1200.00
)
RETURNING id
\gset work_

-- Создаём ремонт.
INSERT INTO repair
    (work_id, master_id, description, cost, status, started_at)
VALUES (
    :work_id,
    :master_id,
    'Замена картриджа',
    1200.00,
    'Выполняется',
    now()
)
RETURNING id
\gset repair_

-- ============================================================
-- ЧАСТЬ 1. Успешная транзакция (COMMIT)
--
-- Завершаем ремонт, фиксируем использованную запчасть,
-- уменьшаем остаток и завершаем работу.
-- Все изменения сохраняются одной транзакцией.
-- ============================================================

BEGIN;

-- Шаг 1. Завершаем ремонт.
UPDATE repair
SET status = 'Завершён',
    result = 'Картридж заменён',
    ended_at = now()
WHERE id = :repair_id;

-- Шаг 2. Фиксируем использование одной запчасти.
INSERT INTO used_part
    (repair_id, part_id, quantity, written_off_at)
VALUES (
    :repair_id,
    :part_id,
    1,
    now()
);

-- Шаг 3. Уменьшаем остаток на складе.
UPDATE part
SET stock_quantity = stock_quantity - 1
WHERE id = :part_id;

-- Шаг 4. Завершаем работу.
UPDATE work
SET status = 'Завершена',
    ended_at = now()
WHERE id = :work_id;

-- Сохраняем все четыре изменения.
COMMIT;

-- Проверяем результат первой транзакции.
SELECT id, status, result
FROM repair
WHERE id = :repair_id;

-- Остаток должен быть равен 1.
SELECT id, stock_quantity
FROM part
WHERE id = :part_id;

-- ============================================================
-- ЧАСТЬ 2. Неудачная транзакция (ROLLBACK)
-- ============================================================

BEGIN;

-- Добавляем запись с количеством 5.
-- ON CONFLICT позволяет не падать, если эта пара уже существует.
INSERT INTO used_part
    (repair_id, part_id, quantity, written_off_at)
VALUES (
    :repair_id,
    :part_id,
    5,
    now()
)
ON CONFLICT (repair_id, part_id) DO NOTHING;

-- Проверяем, что попытка списания нарушает CHECK.
SELECT set_config('demo.part_id', :'part_id', false);

DO $$
DECLARE
    v_part_id integer;
BEGIN
    v_part_id := current_setting('demo.part_id')::integer;

    BEGIN
        UPDATE part
        SET stock_quantity = stock_quantity - 5
        WHERE id = v_part_id;

        RAISE WARNING
            'Ожидаемая ошибка не возникла: проверьте ограничение CHECK';

    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE
                'Ожидаемая ошибка CHECK перехвачена. '
                'Транзакция будет отменена.';
    END;
END;
$$;

ROLLBACK;

-- ============================================================
-- ПРОВЕРКА РЕЗУЛЬТАТОВ
-- ============================================================

-- После ROLLBACK количество записей должно быть 0.
SELECT count(*) AS "должно быть 0"
FROM used_part
WHERE repair_id = :repair_id
  AND part_id = :part_id
  AND quantity = 5;

-- Остаток должен остаться равным 1.
SELECT id, stock_quantity
FROM part
WHERE id = :part_id;

-- Ремонт должен остаться завершённым после первого COMMIT.
SELECT id, status, result
FROM repair
WHERE id = :repair_id;
