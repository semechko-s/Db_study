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
     preliminary_cost, client_approved, approval_at)
VALUES
    (1, 1,
     'Ноутбук сильно нагревается',
     'В ремонте',
     5500.00,
     TRUE,
     CURRENT_TIMESTAMP),

    (2, 1,
     'Смартфон быстро разряжается',
     'Создана',
     4500.00,
     FALSE,
     NULL);

INSERT INTO diagnosis
    (request_id, master_id, result, detected_malfunction)
VALUES
    (1, 2,
     'Система охлаждения загрязнена',
     'Перегрев из-за загрязнения радиатора');

INSERT INTO master_assignment
    (request_id, employee_id, is_active)
VALUES
    (1, 2, TRUE);

INSERT INTO work
    (request_id, status, cost)
VALUES
    (1, 'Выполняется', 5500.00);

INSERT INTO repair
    (work_id, master_id, description, cost, status)
VALUES
    (1, 2, 'Очистка системы охлаждения', 1500.00, 'Выполняется');

INSERT INTO part_reservation
    (repair_id, part_id, quantity, status)
VALUES
    (1, 1, 1, 'Активен');

INSERT INTO payment
    (request_id, amount, paid_at, method, status)
VALUES
    (1, 5500.00, CURRENT_TIMESTAMP, 'Карта', 'Оплачено');

INSERT INTO status_history
    (request_id, old_status, new_status, reason)
VALUES
    (1, 'Создана', 'Принята', 'Оборудование принято в сервисном центре'),
    (1, 'Принята', 'В ремонте', 'Клиент согласовал ремонт');

INSERT INTO notification
    (request_id, event_type, delivery_status)
VALUES
    (1, 'REQUEST_CREATED', 'Отправлено'),
    (1, 'REPAIR_STARTED', 'Отправлено');
