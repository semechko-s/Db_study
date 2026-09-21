-- Тестовые данные для системы сервисного центра
-- Назначение:
-- небольшой согласованный набор данных для проверки
-- связей, ограничений и основных сущностей.
-- Схема должна быть предварительно создана миграциями:
-- 001_create_base_schema.up.sql
-- 002_add_constraints_and_indexes.up.sql

INSERT INTO client (id, full_name, phone, email)
OVERRIDING SYSTEM VALUE
VALUES
    (1, 'Иванов Иван Иванович',
     '+79990000001', 'ivanov@example.com'),

    (2, 'Петрова Анна Сергеевна',
     '+79990000002', 'petrova@example.com'),

    (3, 'ООО "Техносервис"',
     '+79990000003', 'info@technoservice.example');

INSERT INTO employee
    (id, full_name, specialization, phone, email)
OVERRIDING SYSTEM VALUE
VALUES
    (1, 'Оператор Оля', 'Оператор',
     '+79990000010', 'operator@example.com'),

    (2, 'Мастер Миша', 'Мастер',
     '+79990000011', 'master1@example.com'),

    (3, 'Мастер Пётр', 'Мастер',
     '+79990000012', 'master2@example.com'),

    (4, 'Сергей Орлов', 'Менеджер',
     '+79990000013', 'manager@example.com');

INSERT INTO equipment
    (id, client_id, type, manufacturer, model,
     serial_number, condition_description, status)
OVERRIDING SYSTEM VALUE
VALUES
    (
        1,
        1,
        'Ноутбук',
        'Lenovo',
        'ThinkPad T14',
        'LNV-T14-001',
        'Незначительные следы эксплуатации',
        'Зарегистрировано'
    ),

    (
        2,
        2,
        'Смартфон',
        'Samsung',
        'Galaxy S23',
        'SAM-S23-002',
        'Экран без видимых повреждений',
        'Зарегистрировано'
    ),

    (
        3,
        1,
        'Ноутбук',
        'ASUS',
        'VivoBook 15',
        'ASUS-V15-003',
        'Корпус без внешних повреждений',
        'Зарегистрировано'
    ),

    (
        4,
        3,
        'Монитор',
        'Dell',
        'P2422H',
        'DELL-P24-004',
        'Без внешних повреждений',
        'Зарегистрировано'
    );

INSERT INTO part
    (id, name, article, price, stock_quantity)
OVERRIDING SYSTEM VALUE
VALUES
    (1, 'Термопаста Arctic MX-6',
     'TP-MX6-001', 800.00, 10),

    (2, 'Вентилятор Lenovo T14',
     'FAN-T14-002', 2000.00, 5),

    (3, 'Аккумулятор Samsung S23',
     'BAT-S23-003', 4500.00, 4),

    (4, 'Контроллер питания ASUS',
     'PWR-ASUS-004', 8500.00, 2),

    (5, 'Блок питания Dell P2422H',
     'PSU-DELL-005', 3500.00, 3);

-- Клиент определяется через:
-- request -> equipment -> client

INSERT INTO request
    (id, equipment_id, operator_id,
     created_at, received_at, description,
     status, waiting_reason,
     preliminary_cost, total_cost,
     client_approved, approval_at,
     issued_at, completed_at)
OVERRIDING SYSTEM VALUE
VALUES
    (
        1,
        1,
        1,
        '2026-09-01 09:00:00',
        '2026-09-01 09:30:00',
        'Ноутбук сильно нагревается и выключается',
        'Закрыта',
        NULL,
        5500.00,
        5500.00,
        TRUE,
        '2026-09-02 12:00:00',
        '2026-09-05 16:00:00',
        '2026-09-05 16:00:00'
    ),
    (
        2,
        2,
        1,
        '2026-09-03 10:00:00',
        '2026-09-03 10:30:00',
        'Смартфон быстро разряжается',
        'В ремонте',
        NULL,
        6000.00,
        NULL,
        TRUE,
        '2026-09-04 11:00:00',
        NULL,
        NULL
    ),
    (
        3,
        3,
        1,
        '2026-09-04 14:00:00',
        '2026-09-04 14:30:00',
        'Ноутбук не включается',
        'Ожидание',
        'CLIENT_APPROVAL',
        12000.00,
        NULL,
        FALSE,
        NULL,
        NULL,
        NULL
    ),
    (
        4,
        4,
        1,
        '2026-09-05 09:00:00',
        '2026-09-05 09:20:00',
        'Монитор периодически выключается',
        'Отменена',
        NULL,
        4500.00,
        NULL,
        FALSE,
        NULL,
        NULL,
        NULL
    );

INSERT INTO diagnosis
    (id, request_id, master_id,
     performed_at, result, detected_malfunction)
OVERRIDING SYSTEM VALUE
VALUES

    (
        1,
        1,
        2,
        '2026-09-01 11:00:00',
        'Система охлаждения загрязнена',
        'Перегрев из-за загрязнения радиатора'
    ),

    (
        2,
        2,
        2,
        '2026-09-03 12:00:00',
        'Аккумулятор имеет значительный износ',
        'Снижение ёмкости аккумулятора'
    ),

    (
        3,
        3,
        3,
        '2026-09-04 16:00:00',
        'Обнаружена неисправность цепи питания',
        'Неисправен контроллер питания'
    ),

    (
        4,
        4,
        2,
        '2026-09-05 11:00:00',
        'Обнаружена неисправность блока питания',
        'Нестабильная работа блока питания'
    );

INSERT INTO master_assignment
    (id, request_id, employee_id,
     assigned_at, ended_at, is_active)
OVERRIDING SYSTEM VALUE
VALUES

    (
        1,
        1,
        2,
        '2026-09-01 10:00:00',
        '2026-09-02 08:30:00',
        FALSE
    ),

    (
        2,
        1,
        3,
        '2026-09-02 08:30:00',
        '2026-09-05 15:00:00',
        FALSE
    ),

    (
        3,
        2,
        2,
        '2026-09-03 11:00:00',
        NULL,
        TRUE
    ),

    (
        4,
        3,
        3,
        '2026-09-04 15:00:00',
        NULL,
        TRUE
    ),

    (
        5,
        4,
        2,
        '2026-09-05 10:00:00',
        '2026-09-05 12:00:00',
        FALSE
    );

INSERT INTO work
    (id, request_id, started_at,
     ended_at, status, cost)
OVERRIDING SYSTEM VALUE
VALUES
    (
        1,
        1,
        '2026-09-02 09:00:00',
        '2026-09-02 10:30:00',
        'Завершена',
        2500.00
    ),
    (
        2,
        1,
        '2026-09-02 11:00:00',
        '2026-09-03 12:00:00',
        'Завершена',
        3000.00
    ),
    (
        3,
        2,
        '2026-09-04 09:00:00',
        '2026-09-04 10:00:00',
        'Завершена',
        1000.00
    ),
    (
        4,
        2,
        '2026-09-04 10:30:00',
        NULL,
        'Выполняется',
        5000.00
    ),
    (
        5,
        3,
        NULL,
        NULL,
        'Запланирована',
        2000.00
    ),
    (
        6,
        3,
        NULL,
        NULL,
        'Запланирована',
        10000.00
    ),
    (
        7,
        4,
        NULL,
        NULL,
        'Отменена',
        4500.00
    );

INSERT INTO repair
    (id, work_id, master_id,
     description, cost, result,
     started_at, ended_at, status)
OVERRIDING SYSTEM VALUE
VALUES
    (
        1,
        1,
        2,
        'Очистка системы охлаждения',
        1500.00,
        'Радиатор очищен',
        '2026-09-02 09:00:00',
        '2026-09-02 09:45:00',
        'Завершён'
    ),

    (
        2,
        1,
        2,
        'Замена термопасты',
        1000.00,
        'Термопаста заменена',
        '2026-09-02 09:45:00',
        '2026-09-02 10:30:00',
        'Завершён'
    ),

    (
        3,
        2,
        3,
        'Проверка температурного режима',
        1000.00,
        'Температурный режим проверен',
        '2026-09-02 11:00:00',
        '2026-09-02 11:45:00',
        'Завершён'
    ),

    (
        4,
        2,
        3,
        'Замена вентилятора охлаждения',
        2000.00,
        'Вентилятор заменён',
        '2026-09-02 11:45:00',
        '2026-09-03 12:00:00',
        'Завершён'
    ),

    (
        5,
        3,
        2,
        'Диагностическое тестирование аккумулятора',
        1000.00,
        'Износ аккумулятора подтверждён',
        '2026-09-04 09:00:00',
        '2026-09-04 10:00:00',
        'Завершён'
    ),

    (
        6,
        4,
        2,
        'Замена аккумулятора',
        5000.00,
        NULL,
        '2026-09-04 10:30:00',
        NULL,
        'Выполняется'
    ),

    (
        7,
        5,
        3,
        'Проверка цепи питания',
        2000.00,
        NULL,
        NULL,
        NULL,
        'Запланирован'
    ),

    (
        8,
        6,
        3,
        'Замена контроллера питания',
        10000.00,
        NULL,
        NULL,
        NULL,
        'Запланирован'
    ),

    (
        9,
        7,
        2,
        'Замена блока питания',
        4500.00,
        NULL,
        NULL,
        NULL,
        'Отменён'
    );

INSERT INTO part_reservation
    (id, repair_id, part_id,
     quantity, reserved_at, status)
OVERRIDING SYSTEM VALUE
VALUES
    (
        1,
        2,
        1,
        1,
        '2026-09-02 08:00:00',
        'Использован'
    ),

    (
        2,
        4,
        2,
        1,
        '2026-09-02 10:30:00',
        'Использован'
    ),

    (
        3,
        6,
        3,
        1,
        '2026-09-04 10:00:00',
        'Активен'
    ),

    (
        4,
        8,
        4,
        1,
        '2026-09-04 17:00:00',
        'Активен'
    );

INSERT INTO used_part
    (id, repair_id, part_id,
     quantity, written_off_at)
OVERRIDING SYSTEM VALUE
VALUES

    (
        1,
        2,
        1,
        1,
        '2026-09-02 10:30:00'
    ),

    (
        2,
        4,
        2,
        1,
        '2026-09-03 12:00:00'
    );

INSERT INTO payment
    (id, request_id, amount,
     paid_at, method, status)
OVERRIDING SYSTEM VALUE
VALUES

    (
        1,
        1,
        5500.00,
        '2026-09-05 15:30:00',
        'Карта',
        'Оплачено'
    );

INSERT INTO status_history
    (id, request_id, old_status,
     new_status, reason, changed_at)
OVERRIDING SYSTEM VALUE
VALUES

    (
        1, 1, NULL, 'Создана',
        'Заявка зарегистрирована клиентом',
        '2026-09-01 09:00:00'
    ),

    (
        2, 1, 'Создана', 'Принята',
        'Оборудование принято в сервисном центре',
        '2026-09-01 09:30:00'
    ),

    (
        3, 1, 'Принята', 'На диагностике',
        'Мастер приступил к диагностике',
        '2026-09-01 10:00:00'
    ),

    (
        4, 1, 'На диагностике', 'Ожидание',
        'CLIENT_APPROVAL',
        '2026-09-01 12:00:00'
    ),

    (
        5, 1, 'Ожидание', 'В ремонте',
        'Клиент согласовал ремонт',
        '2026-09-02 08:30:00'
    ),

    (
        6, 1, 'В ремонте', 'Готова',
        'Все работы завершены',
        '2026-09-05 14:00:00'
    ),

    (
        7, 1, 'Готова', 'Закрыта',
        'Оборудование выдано, оплата получена',
        '2026-09-05 16:00:00'
    ),

    (
        8, 2, NULL, 'Создана',
        'Заявка зарегистрирована',
        '2026-09-03 10:00:00'
    ),

    (
        9, 2, 'Создана', 'Принята',
        'Оборудование принято',
        '2026-09-03 10:30:00'
    ),

    (
        10, 2, 'Принята', 'На диагностике',
        'Начата диагностика',
        '2026-09-03 11:00:00'
    ),

    (
        11, 2, 'На диагностике', 'Ожидание',
        'CLIENT_APPROVAL',
        '2026-09-03 13:00:00'
    ),

    (
        12, 2, 'Ожидание', 'В ремонте',
        'Клиент согласовал ремонт',
        '2026-09-04 11:00:00'
    ),

    (
        13, 3, NULL, 'Создана',
        'Заявка зарегистрирована',
        '2026-09-04 14:00:00'
    ),

    (
        14, 3, 'Создана', 'Принята',
        'Оборудование принято',
        '2026-09-04 14:30:00'
    ),

    (
        15, 3, 'Принята', 'На диагностике',
        'Начата диагностика',
        '2026-09-04 15:00:00'
    ),

    (
        16, 3, 'На диагностике', 'Ожидание',
        'CLIENT_APPROVAL',
        '2026-09-04 17:00:00'
    ),

    (
        17, 4, NULL, 'Создана',
        'Заявка зарегистрирована',
        '2026-09-05 09:00:00'
    ),

    (
        18, 4, 'Создана', 'Принята',
        'Оборудование принято',
        '2026-09-05 09:20:00'
    ),

    (
        19, 4, 'Принята', 'На диагностике',
        'Начата диагностика',
        '2026-09-05 10:00:00'
    ),

    (
        20, 4, 'На диагностике', 'Отменена',
        'Клиент отказался от ремонта',
        '2026-09-05 12:00:00'
    );

INSERT INTO notification
    (id, request_id, event_type,
     created_at, delivery_status)
OVERRIDING SYSTEM VALUE
VALUES

    (1, 1, 'REQUEST_CREATED',
     '2026-09-01 09:00:00', 'Отправлено'),

    (2, 1, 'DIAGNOSIS_COMPLETED',
     '2026-09-01 12:00:00', 'Отправлено'),

    (3, 1, 'REPAIR_STARTED',
     '2026-09-02 08:30:00', 'Отправлено'),

    (4, 1, 'READY_FOR_PICKUP',
     '2026-09-05 14:00:00', 'Отправлено'),

    (5, 1, 'PAYMENT_RECEIVED',
     '2026-09-05 15:30:00', 'Отправлено'),

    (6, 2, 'DIAGNOSIS_COMPLETED',
     '2026-09-03 13:00:00', 'Отправлено'),

    (7, 3, 'WAITING_CLIENT_APPROVAL',
     '2026-09-04 17:00:00', 'Отправлено'),

    (8, 4, 'REQUEST_CANCELLED',
     '2026-09-05 12:00:00', 'Отправлено');

SELECT setval(
    pg_get_serial_sequence('client', 'id'),
    (SELECT MAX(id) FROM client)
);

SELECT setval(
    pg_get_serial_sequence('employee', 'id'),
    (SELECT MAX(id) FROM employee)
);

SELECT setval(
    pg_get_serial_sequence('equipment', 'id'),
    (SELECT MAX(id) FROM equipment)
);

SELECT setval(
    pg_get_serial_sequence('request', 'id'),
    (SELECT MAX(id) FROM request)
);

SELECT setval(
    pg_get_serial_sequence('master_assignment', 'id'),
    (SELECT MAX(id) FROM master_assignment)
);

SELECT setval(
    pg_get_serial_sequence('diagnosis', 'id'),
    (SELECT MAX(id) FROM diagnosis)
);

SELECT setval(
    pg_get_serial_sequence('work', 'id'),
    (SELECT MAX(id) FROM work)
);

SELECT setval(
    pg_get_serial_sequence('repair', 'id'),
    (SELECT MAX(id) FROM repair)
);

SELECT setval(
    pg_get_serial_sequence('part', 'id'),
    (SELECT MAX(id) FROM part)
);

SELECT setval(
    pg_get_serial_sequence('part_reservation', 'id'),
    (SELECT MAX(id) FROM part_reservation)
);

SELECT setval(
    pg_get_serial_sequence('used_part', 'id'),
    (SELECT MAX(id) FROM used_part)
);

SELECT setval(
    pg_get_serial_sequence('payment', 'id'),
    (SELECT MAX(id) FROM payment)
);

SELECT setval(
    pg_get_serial_sequence('status_history', 'id'),
    (SELECT MAX(id) FROM status_history)
);

SELECT setval(
    pg_get_serial_sequence('notification', 'id'),
    (SELECT MAX(id) FROM notification)
);