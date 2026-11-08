-- Базовые детерминированные данные для SQL-проверок.
-- Загружать только в отдельную тестовую БД после применения миграций.

INSERT INTO client (full_name, phone, email)
VALUES
    ('Иванов Иван Иванович', '+79990000001', 'ivanov@example.com'),
    ('Петрова Анна Сергеевна', '+79990000002', 'petrova@example.com');

INSERT INTO employee (full_name, specialization, phone, email)
VALUES
    ('Оператор Оля', 'Оператор', '+79990000010', 'operator@example.com'),
    ('Мастер Миша', 'Мастер', '+79990000011', 'master@example.com');

INSERT INTO equipment
    (client_id, type, manufacturer, model, serial_number, status)
VALUES
    (1, 'Ноутбук', 'Lenovo', 'ThinkPad T14', 'LNV-T14-001', 'Зарегистрировано'),
    (2, 'Смартфон', 'Samsung', 'Galaxy S23', 'SAM-S23-002', 'Зарегистрировано');

INSERT INTO part (name, article, price, stock_quantity)
VALUES
    ('Термопаста Arctic MX-6', 'TP-MX6-001', 800.00, 10),
    ('Аккумулятор Samsung S23', 'BAT-S23-002', 4500.00, 4);

INSERT INTO request
    (equipment_id, operator_id, description, status,
     preliminary_cost, client_approved, approval_at, created_at)
VALUES
    (1, 1,
     'Ноутбук сильно нагревается',
     'В ремонте',
     5500.00,
     TRUE,
     TIMESTAMP '2026-01-10 08:30:00',
     TIMESTAMP '2026-01-10 09:00:00'),

    (2, 1,
     'Смартфон быстро разряжается',
     'Создана',
     4500.00,
     FALSE,
     NULL,
     TIMESTAMP '2026-01-11 09:00:00');

INSERT INTO diagnosis
    (request_id, master_id, result, detected_malfunction, performed_at)
VALUES
    (1, 2,
     'Система охлаждения загрязнена',
     'Перегрев из-за загрязнения радиатора',
     TIMESTAMP '2026-01-10 09:30:00');

INSERT INTO master_assignment
    (request_id, employee_id, is_active, assigned_at)
VALUES
    (1, 2, TRUE, TIMESTAMP '2026-01-10 09:45:00');

INSERT INTO work
    (request_id, started_at, status, cost)
VALUES
    (1, TIMESTAMP '2026-01-10 10:00:00', 'Выполняется', 5500.00);

INSERT INTO repair
    (work_id, master_id, description, cost, started_at, status)
VALUES
    (1, 2, 'Очистка системы охлаждения', 1500.00,
     TIMESTAMP '2026-01-10 10:15:00', 'Выполняется');

INSERT INTO part_reservation
    (repair_id, part_id, quantity, reserved_at, status)
VALUES
    (1, 1, 1, TIMESTAMP '2026-01-10 10:20:00', 'Активен');

INSERT INTO payment (request_id, amount, paid_at, method, status)
VALUES
    (1, 5500.00, TIMESTAMP '2026-01-15 12:00:00', 'Карта', 'Оплачено');

INSERT INTO status_history
    (request_id, old_status, new_status, reason, changed_at)
VALUES
    (1, 'Создана', 'Принята',
     'Оборудование принято в сервисном центре',
     TIMESTAMP '2026-01-10 10:00:00'),
    (1, 'Принята', 'В ремонте',
     'Клиент согласовал ремонт',
     TIMESTAMP '2026-01-10 12:30:00');

INSERT INTO notification
    (request_id, event_type, created_at, delivery_status)
VALUES
    (1, 'REQUEST_CREATED', TIMESTAMP '2026-01-10 09:05:00', 'Отправлено'),
    (1, 'REPAIR_STARTED', TIMESTAMP '2026-01-10 10:20:00', 'Отправлено');
