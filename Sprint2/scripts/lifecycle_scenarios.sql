
-- ============================================================
-- Система сервисного центра — SQL-сценарии жизненного цикла
-- Все id генерируются автоматически.
-- Связи между записями устанавливаются через RETURNING и
-- переменные psql. Существующие данные не удаляются.
-- ============================================================

\set ON_ERROR_STOP on

-- ============================================================
-- ПОДГОТОВКА ДАННЫХ
-- ============================================================

-- Клиент
INSERT INTO client (full_name, phone, email)
VALUES (
    'Иванов Иван Иванович',
    '+79990000001',
    format('ivanov-%s@example.com', txid_current())
)
RETURNING id
\gset client_

-- Устройство клиента
INSERT INTO equipment
    (client_id, type, manufacturer, model, serial_number, status)
VALUES (
    :client_id,
    'Ноутбук',
    'Acme',
    'A15',
    format('SN-%s', txid_current()),
    'Зарегистрировано'
)
RETURNING id
\gset equipment_

-- Оператор
INSERT INTO employee (full_name, specialization, phone, email)
VALUES (
    'Оператор Оля',
    'Оператор',
    '+79990000002',
    format('operator-%s@example.com', txid_current())
)
RETURNING id
\gset operator_

-- Мастер Миша
INSERT INTO employee (full_name, specialization, phone, email)
VALUES (
    'Мастер Миша',
    'Мастер',
    '+79990000003',
    format('master-%s@example.com', txid_current())
)
RETURNING id
\gset master_

-- Запчасть: термопаста
INSERT INTO part (name, article, price, stock_quantity)
VALUES (
    'Термопаста',
    format('TP-%s', txid_current()),
    300.00,
    10
)
RETURNING id
\gset part_

-- ============================================================
-- СЦЕНАРИЙ 1. Полный путь заявки от создания до закрытия
-- ============================================================

-- Шаг 1. Клиент создаёт заявку.
INSERT INTO request
    (equipment_id, description, status, created_at)
VALUES (
    :equipment_id,
    'Ноутбук сильно греется и выключается',
    'Создана',
    now()
)
RETURNING id
\gset request1_

INSERT INTO status_history
    (request_id, old_status, new_status, reason, changed_at)
VALUES (
    :request1_id,
    NULL,
    'Создана',
    'Заявка зарегистрирована клиентом',
    now()
);

-- Шаг 2. Оператор принимает устройство.
UPDATE request
SET status = 'Принята',
    operator_id = :operator_id,
    received_at = now()
WHERE id = :request1_id;

INSERT INTO status_history
    (request_id, old_status, new_status, reason, changed_at)
VALUES (
    :request1_id,
    'Создана',
    'Принята',
    'Устройство физически принято в сервис',
    now()
);

-- Назначаем мастера.
INSERT INTO master_assignment
    (request_id, employee_id, assigned_at, is_active)
VALUES (
    :request1_id,
    :master_id,
    now(),
    true
);

-- Шаг 3. Мастер проводит диагностику.
UPDATE request
SET status = 'На диагностике'
WHERE id = :request1_id;

INSERT INTO status_history
    (request_id, old_status, new_status, reason, changed_at)
VALUES (
    :request1_id,
    'Принята',
    'На диагностике',
    'Мастер приступил к диагностике',
    now()
);

INSERT INTO diagnosis
    (request_id, master_id, performed_at, result, detected_malfunction)
VALUES (
    :request1_id,
    :master_id,
    now(),
    'Обнаружен засор системы охлаждения',
    'Перегрев из-за забитого радиатора'
);

-- Создаём работу.
INSERT INTO work (request_id, status, cost)
VALUES (
    :request1_id,
    'Запланирована',
    0
)
RETURNING id
\gset work1_

-- Создаём ремонт.
INSERT INTO repair
    (work_id, master_id, description, cost, status)
VALUES (
    :work1_id,
    :master_id,
    'Очистка радиатора и замена термопасты',
    800.00,
    'Запланирован'
)
RETURNING id
\gset repair1_

-- Диагностика завершена, ожидаем согласия клиента.
UPDATE request
SET status = 'Ожидание',
    waiting_reason = 'CLIENT_APPROVAL',
    preliminary_cost = 800.00
WHERE id = :request1_id;

INSERT INTO status_history
    (request_id, old_status, new_status, reason, changed_at)
VALUES (
    :request1_id,
    'На диагностике',
    'Ожидание',
    'CLIENT_APPROVAL',
    now()
);

-- Шаг 4. Клиент соглашается на ремонт.
UPDATE request
SET status = 'В ремонте',
    client_approved = true,
    approval_at = now(),
    waiting_reason = NULL
WHERE id = :request1_id;

INSERT INTO status_history
    (request_id, old_status, new_status, reason, changed_at)
VALUES (
    :request1_id,
    'Ожидание',
    'В ремонте',
    'Клиент согласовал ремонт',
    now()
);

UPDATE work
SET status = 'Согласована',
    cost = 800.00
WHERE id = :work1_id;

UPDATE work
SET status = 'Выполняется',
    started_at = now()
WHERE id = :work1_id;

UPDATE repair
SET status = 'Выполняется',
    started_at = now()
WHERE id = :repair1_id;

-- Шаг 5. Резервируем запчасть.
INSERT INTO part_reservation
    (repair_id, part_id, quantity, status)
VALUES (
    :repair1_id,
    :part_id,
    1,
    'Активен'
);

-- Шаг 6. Завершаем ремонт.
UPDATE repair
SET status = 'Завершён',
    result = 'Радиатор очищен, термопаста заменена',
    ended_at = now()
WHERE id = :repair1_id;

INSERT INTO used_part
    (repair_id, part_id, quantity, written_off_at)
VALUES (
    :repair1_id,
    :part_id,
    1,
    now()
);

UPDATE part_reservation
SET status = 'Использован'
WHERE repair_id = :repair1_id
  AND part_id = :part_id;

UPDATE part
SET stock_quantity = stock_quantity - 1
WHERE id = :part_id;

UPDATE work
SET status = 'Завершена',
    ended_at = now()
WHERE id = :work1_id;

-- Заявка готова к выдаче.
UPDATE request
SET status = 'Готова',
    total_cost = 800.00
WHERE id = :request1_id;

INSERT INTO status_history
    (request_id, old_status, new_status, reason, changed_at)
VALUES (
    :request1_id,
    'В ремонте',
    'Готова',
    'Ремонт завершён',
    now()
);

-- Шаг 7. Оплата и выдача устройства.
INSERT INTO payment
    (request_id, amount, paid_at, method, status)
VALUES (
    :request1_id,
    800.00,
    now(),
    'Наличные',
    'Оплачено'
);

UPDATE request
SET status = 'Закрыта',
    issued_at = now(),
    completed_at = now()
WHERE id = :request1_id;

INSERT INTO status_history
    (request_id, old_status, new_status, reason, changed_at)
VALUES (
    :request1_id,
    'Готова',
    'Закрыта',
    'Устройство выдано клиенту, оплата получена',
    now()
);

-- ============================================================
-- СЦЕНАРИЙ 2. Замена мастера на действующей заявке
-- ============================================================

-- Новый мастер Пётр.
INSERT INTO employee (full_name, specialization)
VALUES ('Мастер Пётр', 'Мастер')
RETURNING id
\gset master_petr_

-- Новая заявка на то же устройство.
INSERT INTO request
    (equipment_id, description, status, created_at)
VALUES (
    :equipment_id,
    'Не включается клавиатура',
    'На диагностике',
    now()
)
RETURNING id
\gset request2_

-- Первоначальное назначение мастера Миши.
INSERT INTO master_assignment
    (request_id, employee_id, assigned_at, is_active)
VALUES (
    :request2_id,
    :master_id,
    now(),
    true
)
RETURNING id
\gset assignment2_

-- Закрываем старое назначение.
UPDATE master_assignment
SET is_active = false,
    ended_at = now()
WHERE id = :assignment2_id;

-- Назначаем мастера Петра без повторного создания заявки.
INSERT INTO master_assignment
    (request_id, employee_id, assigned_at, is_active)
VALUES (
    :request2_id,
    :master_petr_id,
    now(),
    true
);

-- ============================================================
-- СЦЕНАРИЙ 3. Нехватка запчасти во время ремонта
-- ============================================================

-- Создаём заявку.
INSERT INTO request
    (equipment_id, description, status,
     client_approved, approval_at, created_at)
VALUES (
    :equipment_id,
    'Замена вентилятора и чистка от пыли',
    'В ремонте',
    true,
    now(),
    now()
)
RETURNING id
\gset request3_

-- Работа по заявке.
INSERT INTO work (request_id, status, started_at, cost)
VALUES (
    :request3_id,
    'Выполняется',
    now(),
    0
)
RETURNING id
\gset work3_

-- Ремонт 1: чистка от пыли.
INSERT INTO repair
    (work_id, master_id, description, cost, status, started_at)
VALUES (
    :work3_id,
    :master_id,
    'Чистка от пыли',
    400.00,
    'Выполняется',
    now()
)
RETURNING id
\gset repair_dust_

-- Ремонт 2: замена вентилятора.
INSERT INTO repair
    (work_id, master_id, description, cost, status, started_at)
VALUES (
    :work3_id,
    :master_id,
    'Замена вентилятора',
    500.00,
    'Выполняется',
    now()
)
RETURNING id
\gset repair_fan_

-- На складе нет вентиляторов.
INSERT INTO part (name, article, price, stock_quantity)
VALUES (
    'Вентилятор охлаждения',
    format('FAN-%s', txid_current()),
    700.00,
    0
)
RETURNING id
\gset part_fan_

-- Приостанавливаем только ремонт замены вентилятора.
UPDATE repair
SET status = 'Приостановлен'
WHERE id = :repair_fan_id;

-- Чистка от пыли завершается независимо.
UPDATE repair
SET status = 'Завершён',
    result = 'Пыль удалена',
    ended_at = now()
WHERE id = :repair_dust_id;

-- Поступило пять вентиляторов.
UPDATE part
SET stock_quantity = stock_quantity + 5
WHERE id = :part_fan_id;

-- Резервируем вентилятор и возобновляем ремонт.
INSERT INTO part_reservation
    (repair_id, part_id, quantity, status)
VALUES (
    :repair_fan_id,
    :part_fan_id,
    1,
    'Активен'
);

UPDATE repair
SET status = 'Выполняется'
WHERE id = :repair_fan_id;

-- ============================================================
-- ПРОВЕРКА РЕЗУЛЬТАТОВ
-- ============================================================

SELECT id, status, total_cost
FROM request
WHERE id IN (:request1_id, :request2_id, :request3_id)
ORDER BY id;

SELECT id, status, result
FROM repair
WHERE id IN (:repair1_id, :repair_dust_id, :repair_fan_id)
ORDER BY id;

SELECT id, name, stock_quantity
FROM part
WHERE id IN (:part_id, :part_fan_id)
ORDER BY id;
