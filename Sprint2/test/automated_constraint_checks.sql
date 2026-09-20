-- ============================================================
-- Система сервисного центра — автоматизированная проверка схемы
-- Автор раздела: Максим (КТ-02, желательный пункт: автоматизировать
-- проверку схемы и ограничений)
--
-- Проверяет ограничения из 001_initial_schema.up.sql И
-- 002_add_missing_constraints.up.sql. Запускать ПОСЛЕ применения
-- обеих миграций.
--
-- Как это работает:
-- 1. Скрипт создаёт минимальный набор базовых данных внутри ОДНОЙ
--    большой транзакции.
-- 2. Для каждого теста используется SAVEPOINT: скрипт пытается
--    выполнить операцию, которая ДОЛЖНА быть отклонена базой.
--    Если база её отклонила — тест PASS. Если пропустила — FAIL.
--    Есть и обратные тесты: корректные данные должны проходить.
-- 3. После каждой попытки — ROLLBACK TO SAVEPOINT: тест не оставляет
--    след в базе, скрипт можно гонять сколько угодно раз.
-- 4. В конце — ROLLBACK всей транзакции: скрипт ничего не меняет
--    в базе, только проверяет.
--
-- Запуск: psql -f automated_constraint_checks.sql имя_базы
-- ============================================================

BEGIN;

CREATE TEMP TABLE test_results (
    id      SERIAL PRIMARY KEY,
    name    TEXT NOT NULL,
    status  TEXT NOT NULL,
    detail  TEXT
);

CREATE OR REPLACE FUNCTION pg_temp.assert_rejected(test_name TEXT, stmt TEXT)
RETURNS void AS $$
BEGIN
    SAVEPOINT sp_test;
    EXECUTE stmt;
    ROLLBACK TO SAVEPOINT sp_test;
    INSERT INTO test_results (name, status, detail)
    VALUES (test_name, 'FAIL', 'Ожидалось отклонение, но операция прошла');
EXCEPTION WHEN OTHERS THEN
    ROLLBACK TO SAVEPOINT sp_test;
    INSERT INTO test_results (name, status, detail)
    VALUES (test_name, 'PASS', 'Отклонено как ожидалось: ' || SQLERRM);
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION pg_temp.assert_accepted(test_name TEXT, stmt TEXT)
RETURNS void AS $$
BEGIN
    SAVEPOINT sp_test;
    EXECUTE stmt;
    ROLLBACK TO SAVEPOINT sp_test;
    INSERT INTO test_results (name, status, detail)
    VALUES (test_name, 'PASS', 'Корректные данные приняты, как ожидалось');
EXCEPTION WHEN OTHERS THEN
    ROLLBACK TO SAVEPOINT sp_test;
    INSERT INTO test_results (name, status, detail)
    VALUES (test_name, 'FAIL', 'Корректные данные ошибочно отклонены: ' || SQLERRM);
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- Базовые данные для тестов
-- ------------------------------------------------------------

INSERT INTO client (id, full_name, phone) VALUES (9001, 'Тестовый клиент', '+70000000000');
INSERT INTO equipment (id, client_id, type, manufacturer, model, status)
VALUES (9001, 9001, 'Ноутбук', 'TestBrand', 'X1', 'REGISTERED');
INSERT INTO employee (id, full_name, specialization) VALUES (9001, 'Тестовый оператор', 'Оператор');
INSERT INTO employee (id, full_name, specialization) VALUES (9002, 'Тестовый мастер', 'Мастер');
INSERT INTO employee (id, full_name, specialization) VALUES (9003, 'Второй тестовый мастер', 'Мастер');
INSERT INTO request (id, equipment_id, operator_id, description, status)
VALUES (9001, 9001, 9001, 'Тестовая неисправность', 'ACCEPTED');
INSERT INTO work (id, request_id, status) VALUES (9001, 9001, 'IN_PROGRESS');
INSERT INTO repair (id, work_id, master_id, description, cost, status)
VALUES (9001, 9001, 9002, 'Тестовый ремонт', 100.00, 'IN_PROGRESS');
INSERT INTO part (id, name, article, price, stock_quantity)
VALUES (9001, 'Тестовая запчасть', 'TEST-001', 50.00, 5);


-- ============================================================
-- НЕГАТИВНЫЕ ТЕСТЫ — все эти операции ДОЛЖНЫ быть отклонены
-- ============================================================

-- 1. NOT NULL: заявка без описания неисправности (правило 2)
SELECT pg_temp.assert_rejected(
    '01: request без description (NOT NULL)',
    $$INSERT INTO request (equipment_id, description) VALUES (9001, NULL)$$
);

-- 2. CHECK: недопустимое значение статуса заявки
SELECT pg_temp.assert_rejected(
    '02: request с несуществующим статусом',
    $$INSERT INTO request (equipment_id, description, status)
      VALUES (9001, 'тест', 'NOT_A_STATUS')$$
);

-- 3. CHECK: статус WAITING без обязательного кода причины (правило 6, миграция 002)
SELECT pg_temp.assert_rejected(
    '03: статус WAITING без waiting_reason',
    $$INSERT INTO request (equipment_id, description, status)
      VALUES (9001, 'тест', 'WAITING')$$
);

-- 3b. CHECK: код причины указан, но статус НЕ WAITING (обратная сторона того же правила)
SELECT pg_temp.assert_rejected(
    '03b: waiting_reason указан при статусе CREATED',
    $$INSERT INTO request (equipment_id, description, status, waiting_reason)
      VALUES (9001, 'тест', 'CREATED', 'PART_WAITING')$$
);

-- 4. CHECK: переход в IN_REPAIR без согласия клиента (правило 7, миграция 002)
SELECT pg_temp.assert_rejected(
    '04: статус IN_REPAIR без client_approved',
    $$INSERT INTO request (equipment_id, description, status, client_approved)
      VALUES (9001, 'тест', 'IN_REPAIR', false)$$
);

-- 5. Частичный UNIQUE INDEX: два активных мастера на одну заявку (правило 5)
SELECT pg_temp.assert_rejected(
    '05: два активных назначения мастера на одну заявку подряд',
    $$DO $inner$
      BEGIN
        INSERT INTO master_assignment (request_id, employee_id, is_active) VALUES (9001, 9002, true);
        INSERT INTO master_assignment (request_id, employee_id, is_active) VALUES (9001, 9003, true);
      END
      $inner$$$
);

-- 6. Частичный UNIQUE INDEX: повторный активный резерв той же запчасти (правило 9, миграция 002)
SELECT pg_temp.assert_rejected(
    '06: повторное резервирование той же запчасти под тот же ремонт',
    $$DO $inner$
      BEGIN
        INSERT INTO part_reservation (repair_id, part_id, quantity, status) VALUES (9001, 9001, 1, 'ACTIVE');
        INSERT INTO part_reservation (repair_id, part_id, quantity, status) VALUES (9001, 9001, 1, 'ACTIVE');
      END
      $inner$$$
);

-- 7. CHECK: нулевая оплата со статусом PAID вместо NOT_REQUIRED (правило 14, миграция 002)
SELECT pg_temp.assert_rejected(
    '07: amount=0 со статусом PAID',
    $$INSERT INTO payment (request_id, amount, status) VALUES (9001, 0, 'PAID')$$
);

-- 8. CHECK: недопустимый статус оборудования (миграция 002)
SELECT pg_temp.assert_rejected(
    '08: equipment с несуществующим статусом',
    $$UPDATE equipment SET status = 'BROKEN_FOREVER' WHERE id = 9001$$
);

-- 9. CHECK: недопустимый статус работы (миграция 002)
SELECT pg_temp.assert_rejected(
    '09: work с несуществующим статусом',
    $$UPDATE work SET status = 'FROZEN' WHERE id = 9001$$
);

-- 10. CHECK: отрицательная стоимость ремонта
SELECT pg_temp.assert_rejected(
    '10: repair.cost < 0',
    $$INSERT INTO repair (work_id, master_id, description, cost, status)
      VALUES (9001, 9002, 'тест', -100, 'PLANNED')$$
);

-- 11. CHECK: отрицательный остаток на складе
SELECT pg_temp.assert_rejected(
    '11: part.stock_quantity < 0',
    $$UPDATE part SET stock_quantity = -1 WHERE id = 9001$$
);

-- 12. FOREIGN KEY: заявка ссылается на несуществующее оборудование
SELECT pg_temp.assert_rejected(
    '12: request.equipment_id указывает на несуществующую запись',
    $$INSERT INTO request (equipment_id, description) VALUES (999999, 'тест')$$
);

-- 13. UNIQUE: дублирующийся артикул запчасти
SELECT pg_temp.assert_rejected(
    '13: повторный article у part',
    $$INSERT INTO part (name, article, price, stock_quantity) VALUES ('Дубликат', 'TEST-001', 10, 1)$$
);

-- 14. CHECK: запись истории статуса без реального изменения (old = new, миграция 002)
SELECT pg_temp.assert_rejected(
    '14: status_history с одинаковым old_status и new_status',
    $$INSERT INTO status_history (request_id, old_status, new_status)
      VALUES (9001, 'ACCEPTED', 'ACCEPTED')$$
);

-- 15. CHECK: недопустимый статус доставки уведомления (миграция 002)
SELECT pg_temp.assert_rejected(
    '15: notification с несуществующим delivery_status',
    $$INSERT INTO notification (request_id, event_type, delivery_status)
      VALUES (9001, 'test_event', 'LOST_IN_SPACE')$$
);

-- 16. CHECK: заявка закрыта, но устройство не выдано (правило 13, миграция 002)
SELECT pg_temp.assert_rejected(
    '16: status CLOSED без issued_at',
    $$INSERT INTO request (equipment_id, description, status, client_approved, approval_at, issued_at)
      VALUES (9001, 'тест', 'CLOSED', true, now(), NULL)$$
);


-- ============================================================
-- КОНТРОЛЬНЫЕ ТЕСТЫ — эти операции ДОЛЖНЫ пройти без ошибок
-- ============================================================

-- 17. Корректная заявка со всеми обязательными полями
SELECT pg_temp.assert_accepted(
    '17: корректная заявка проходит',
    $$INSERT INTO request (equipment_id, description, status) VALUES (9001, 'норм. заявка', 'CREATED')$$
);

-- 18. Корректный переход в WAITING с указанной причиной
SELECT pg_temp.assert_accepted(
    '18: WAITING с корректным waiting_reason',
    $$INSERT INTO request (equipment_id, description, status, waiting_reason)
      VALUES (9001, 'норм. заявка', 'WAITING', 'PART_WAITING')$$
);

-- 19. Гарантийный случай: нулевая стоимость со статусом NOT_REQUIRED (правило 14)
SELECT pg_temp.assert_accepted(
    '19: amount=0 со статусом NOT_REQUIRED — гарантийный случай',
    $$INSERT INTO payment (request_id, amount, status) VALUES (9001, 0, 'NOT_REQUIRED')$$
);

-- 20. Корректное назначение одного активного мастера на заявку без активного
SELECT pg_temp.assert_accepted(
    '20: обычное назначение мастера проходит',
    $$INSERT INTO master_assignment (request_id, employee_id, is_active) VALUES (9001, 9002, true)$$
);


-- ============================================================
-- ИТОГ: сводная таблица результатов
-- ============================================================

SELECT
    name AS "Тест",
    status AS "Результат",
    detail AS "Подробности"
FROM test_results
ORDER BY id;

DO $$
DECLARE
    total_count  INT;
    fail_count   INT;
BEGIN
    SELECT count(*) INTO total_count FROM test_results;
    SELECT count(*) INTO fail_count FROM test_results WHERE status = 'FAIL';

    IF fail_count = 0 THEN
        RAISE NOTICE 'ВСЕ ТЕСТЫ ПРОЙДЕНЫ: % из %', total_count, total_count;
    ELSE
        RAISE WARNING 'ЕСТЬ ПРОВАЛЕННЫЕ ТЕСТЫ: % из % провалено', fail_count, total_count;
    END IF;
END $$;

-- Ничего не сохраняем: весь скрипт — только проверка, база не меняется.
ROLLBACK;
