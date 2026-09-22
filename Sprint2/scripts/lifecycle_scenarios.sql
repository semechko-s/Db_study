-- Система сервисного центра — SQL-сценарии жизненного цикла
--  (КТ-02, обязательный пункт: сценарии
-- жизненного цикла минимум трёх основных сущностей)
--
-- Статусы приведены в соответствие с текущей схемой команды:
-- 001_create_base_schema.up.sql + 002_add_constraints_and_indexes.up.sql
-- (статусы на русском: 'Создана', 'Ожидание', 'В ремонте' и т.д.;
-- коды причины ожидания остаются английскими: CLIENT_APPROVAL,
-- PART_WAITING, ADDITIONAL_DIAGNOSTICS, OTHER — как в
-- request_waiting_reason_values_chk).
--
-- СЦЕНАРИЙ 1. Полный путь заявки от создания до закрытия
-- Затрагивает: client, equipment, employee, request, master_assignment,
--              diagnosis, work, repair, part, part_reservation,
--              used_part, payment, status_history

-- Справочные данные: клиент, устройство, оператор, мастер, запчасть.
INSERT INTO client (id, full_name, phone, email)
VALUES (1, 'Иванов Иван Иванович', '+79990000001', 'ivanov@example.com');

INSERT INTO equipment (id, client_id, type, manufacturer, model, serial_number, status)
VALUES (1, 1, 'Ноутбук', 'Acme', 'A15', 'SN-0001', 'Зарегистрировано');

INSERT INTO employee (id, full_name, specialization, phone, email)
VALUES
    (1, 'Оператор Оля', 'Оператор', '+79990000002', 'operator@example.com'),
    (2, 'Мастер Миша',  'Мастер',   '+79990000003', 'master@example.com');

INSERT INTO part (id, name, article, price, stock_quantity)
VALUES (1, 'Термопаста', 'TP-001', 300.00, 10);


-- Шаг 1. Клиент создаёт заявку (сценарий 1 README: «Создание заявки»).
-- Правило 2: обязательны клиент (через устройство), описание неисправности.
INSERT INTO request (id, equipment_id, description, status, created_at)
VALUES (1, 1, 'Ноутбук сильно греется и выключается', 'Создана', now());

INSERT INTO status_history (request_id, old_status, new_status, reason, changed_at)
VALUES (1, NULL, 'Создана', 'Заявка зарегистрирована клиентом', now());


-- Шаг 2. Оператор принимает устройство (сценарий 2 README).
-- Правило 4: приём переводит заявку в «Принята» и запускает поиск мастера.
UPDATE request
SET status = 'Принята', operator_id = 1, received_at = now()
WHERE id = 1;

INSERT INTO status_history (request_id, old_status, new_status, reason, changed_at)
VALUES (1, 'Создана', 'Принята', 'Устройство физически принято в сервис', now());

-- Назначаем мастера отдельной записью (правило 5).
INSERT INTO master_assignment (request_id, employee_id, assigned_at, is_active)
VALUES (1, 2, now(), true);


-- Шаг 3. Мастер проводит диагностику (сценарий 3 README).
UPDATE request
SET status = 'На диагностике'
WHERE id = 1;

INSERT INTO status_history (request_id, old_status, new_status, reason, changed_at)
VALUES (1, 'Принята', 'На диагностике', 'Мастер приступил к диагностике', now());

INSERT INTO diagnosis (request_id, master_id, performed_at, result, detected_malfunction)
VALUES (1, 2, now(), 'Обнаружен засор системы охлаждения', 'Перегрев из-за забитого радиатора');

-- По результатам диагностики формируется работа и входящие в неё ремонты.
INSERT INTO work (id, request_id, status, cost)
VALUES (1, 1, 'Запланирована', 0);

INSERT INTO repair (id, work_id, master_id, description, cost, status)
VALUES (1, 1, 2, 'Очистка радиатора и замена термопасты', 800.00, 'Запланирован');

-- Диагностика завершена — заявка уходит в «Ожидание» с причиной
-- «ждём решения клиента» (правило 6: код причины обязателен).
UPDATE request
SET status = 'Ожидание', waiting_reason = 'CLIENT_APPROVAL', preliminary_cost = 800.00
WHERE id = 1;

INSERT INTO status_history (request_id, old_status, new_status, reason, changed_at)
VALUES (1, 'На диагностике', 'Ожидание', 'CLIENT_APPROVAL', now());


-- Шаг 4. Клиент соглашается на ремонт (сценарий 4 README).
-- Правило 7: без согласия клиента переход в «В ремонте» невозможен.
UPDATE request
SET status = 'В ремонте', client_approved = true, approval_at = now(), waiting_reason = NULL
WHERE id = 1;

INSERT INTO status_history (request_id, old_status, new_status, reason, changed_at)
VALUES (1, 'Ожидание', 'В ремонте', 'Клиент согласовал ремонт', now());

UPDATE work SET status = 'Согласована', cost = 800.00 WHERE id = 1;
UPDATE work SET status = 'Выполняется', started_at = now() WHERE id = 1;
UPDATE repair SET status = 'Выполняется', started_at = now() WHERE id = 1;


-- Шаг 5. Мастер резервирует запчасть под конкретный ремонт.
-- Правило 9: одна и та же запчасть не резервируется дважды одним
-- активным резервом — гарантируется уникальным индексом.
INSERT INTO part_reservation (repair_id, part_id, quantity, status)
VALUES (1, 1, 1, 'Активен');


-- Шаг 6. Ремонт завершён (сценарий 5 README).
-- Правило 10: запчасть списывается строго при завершении конкретного
-- ремонта, а не всей заявки.
UPDATE repair
SET status = 'Завершён', result = 'Радиатор очищен, термопаста заменена', ended_at = now()
WHERE id = 1;

INSERT INTO used_part (repair_id, part_id, quantity, written_off_at)
VALUES (1, 1, 1, now());

UPDATE part_reservation SET status = 'Использован' WHERE repair_id = 1 AND part_id = 1;
UPDATE part SET stock_quantity = stock_quantity - 1 WHERE id = 1;

UPDATE work SET status = 'Завершена', ended_at = now() WHERE id = 1;

-- Все ремонты в рамках заявки завершены — заявка готова к выдаче.
UPDATE request
SET status = 'Готова', total_cost = 800.00
WHERE id = 1;

INSERT INTO status_history (request_id, old_status, new_status, reason, changed_at)
VALUES (1, 'В ремонте', 'Готова', 'Ремонт завершён', now());


-- Шаг 7. Оплата и выдача устройства (сценарий 6 README).
-- Правило 13: заявка закрывается только после зафиксированной оплаты,
-- равной итоговой стоимости, и факта выдачи устройства.
INSERT INTO payment (request_id, amount, paid_at, method, status)
VALUES (1, 800.00, now(), 'Наличные', 'Оплачено');

UPDATE request
SET status = 'Закрыта', issued_at = now(), completed_at = now()
WHERE id = 1;

INSERT INTO status_history (request_id, old_status, new_status, reason, changed_at)
VALUES (1, 'Готова', 'Закрыта', 'Устройство выдано клиенту, оплата получена', now());


-- СЦЕНАРИЙ 2. Замена мастера на действующей заявке
-- Затрагивает: master_assignment
-- Правило 5: мастера можно заменить на любом этапе без повторной
-- диагностики; в любой момент активен только один мастер.

INSERT INTO employee (id, full_name, specialization)
VALUES (3, 'Мастер Пётр', 'Мастер');

INSERT INTO request (id, equipment_id, description, status, created_at)
VALUES (2, 1, 'Не включается клавиатура', 'На диагностике', now());

-- Мастер Миша назначен и уже начал диагностику.
INSERT INTO master_assignment (id, request_id, employee_id, assigned_at, is_active)
VALUES (10, 2, 2, now(), true);

-- Мастер Миша заболел / ушёл в отпуск — нужна замена.
-- Сначала закрываем текущее активное назначение...
UPDATE master_assignment
SET is_active = false, ended_at = now()
WHERE id = 10;

-- ...затем создаём новое на мастера Петра. Заявка НЕ возвращается
-- в «На диагностике» заново (её статус не трогаем) — это и есть
-- требование правила 5 «без повторного проведения диагностики».
INSERT INTO master_assignment (request_id, employee_id, assigned_at, is_active)
VALUES (2, 3, now(), true);

-- Проверка: попытка вставить второе активное назначение на ту же
-- заявку, не закрыв первое, была бы отклонена уникальным индексом
-- uq_master_assignment_one_active_per_request.


-- ============================================================
-- СЦЕНАРИЙ 3. Нехватка запчасти во время ремонта
-- Затрагивает: part, part_reservation, repair
-- Правило 11 (второй случай): если запчасти не хватает уже во время
-- ремонта, приостанавливается конкретный ремонт (статус
-- «Приостановлен»), а не вся заявка — статус заявки остаётся
-- «В ремонте».
-- ============================================================

INSERT INTO request (id, equipment_id, description, status, client_approved, approval_at, created_at)
VALUES (3, 1, 'Замена вентилятора и чистка от пыли', 'В ремонте', true, now(), now());

INSERT INTO work (id, request_id, status, started_at, cost)
VALUES (2, 3, 'Выполняется', now(), 0);

INSERT INTO repair (id, work_id, master_id, description, cost, status, started_at)
VALUES
    (2, 2, 2, 'Чистка от пыли', 400.00, 'Выполняется', now()),
    (3, 2, 2, 'Замена вентилятора', 500.00, 'Выполняется', now());

-- На складе закончился нужный вентилятор.
INSERT INTO part (id, name, article, price, stock_quantity)
VALUES (2, 'Вентилятор охлаждения', 'FAN-001', 700.00, 0);

-- Ремонт «Чистка от пыли» не зависит от этой детали — продолжается.
-- А ремонт «Замена вентилятора» приостанавливаем: статус меняется
-- у КОНКРЕТНОГО ремонта, статус заявки («В ремонте») не трогаем.
UPDATE repair
SET status = 'Приостановлен'
WHERE id = 3;

-- Первый ремонт спокойно завершается независимо от второго.
UPDATE repair
SET status = 'Завершён', result = 'Пыль удалена', ended_at = now()
WHERE id = 2;
-- Этот ремонт обошёлся без запчастей — used_part для него не создаётся.

-- Через несколько дней вентилятор поступил на склад.
UPDATE part SET stock_quantity = stock_quantity + 5 WHERE id = 2;

-- Резервируем деталь и возобновляем приостановленный ремонт.
INSERT INTO part_reservation (repair_id, part_id, quantity, status)
VALUES (3, 2, 1, 'Активен');

UPDATE repair
SET status = 'Выполняется'
WHERE id = 3;

-- Заявка «request 3» всё это время оставалась в статусе «В ремонте»
-- и ни разу не уходила в «Ожидание» — именно это и проверяет правило 11.
