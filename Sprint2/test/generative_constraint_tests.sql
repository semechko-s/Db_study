BEGIN;

TRUNCATE
    notification,
    status_history,
    payment,
    used_part,
    part_reservation,
    repair,
    work,
    diagnosis,
    master_assignment,
    request,
    equipment,
    part,
    employee,
    client
RESTART IDENTITY CASCADE;

-- Базовые данные

INSERT INTO client(full_name, phone)
VALUES ('Клиент 1', '111');

INSERT INTO employee(full_name, specialization)
VALUES
    ('Оператор', 'Оператор'),
    ('Мастер', 'Мастер');

INSERT INTO equipment(client_id, type, manufacturer, model, status)
VALUES
    (1, 'Ноутбук', 'Test', 'Model', 'Зарегистрировано');

INSERT INTO request(equipment_id, description)
VALUES
    (1, 'Тестовая заявка');

INSERT INTO work(request_id, cost)
VALUES
    (1, 100);

INSERT INTO repair(work_id, master_id, description, cost)
VALUES
    (1, 2, 'Ремонт', 100);

INSERT INTO part(name, price)
VALUES
    ('Деталь', 100);

-- CHECK: client

DO $$
BEGIN
    BEGIN
        INSERT INTO client(full_name)
        VALUES ('Ошибка');

        RAISE EXCEPTION 'client_contact_present FAILED';

    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
END $$;

-- CHECK: equipment status

DO $$
BEGIN
    BEGIN
        INSERT INTO equipment(
            client_id,
            type,
            manufacturer,
            model,
            status
        )
        VALUES (1, 'x', 'x', 'x', 'Ошибка');

        RAISE EXCEPTION 'equipment_status_chk FAILED';

    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
END $$;

-- CHECK: request status

DO $$
BEGIN
    BEGIN
        INSERT INTO request(
            equipment_id,
            description,
            status
        )
        VALUES (1, 'x', 'Ошибка');

        RAISE EXCEPTION 'request_status_chk FAILED';

    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
END $$;

-- CHECK: waiting_reason

DO $$
BEGIN
    BEGIN
        INSERT INTO request(
            equipment_id,
            description,
            status,
            waiting_reason
        )
        VALUES (1, 'x', 'Ожидание', NULL);

        RAISE EXCEPTION 'request_waiting_reason_chk FAILED';

    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
END $$;

-- CHECK: work cost

DO $$
BEGIN
    BEGIN
        INSERT INTO work(request_id, cost)
        VALUES (1, -1);

        RAISE EXCEPTION 'work_cost_chk FAILED';

    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
END $$;

-- CHECK: repair status

DO $$
BEGIN
    BEGIN
        INSERT INTO repair(
            work_id,
            master_id,
            description,
            cost,
            status
        )
        VALUES (1, 2, 'x', 1, 'Ошибка');

        RAISE EXCEPTION 'repair_status_chk FAILED';

    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
END $$;

-- CHECK: completed repair requires result

DO $$
BEGIN
    BEGIN
        INSERT INTO repair(
            work_id,
            master_id,
            description,
            cost,
            status
        )
        VALUES (1, 2, 'x', 1, 'Завершён');

        RAISE EXCEPTION 'repair_result_when_completed_chk FAILED';

    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
END $$;

-- CHECK: part price

DO $$
BEGIN
    BEGIN
        INSERT INTO part(name, price)
        VALUES ('x', -1);

        RAISE EXCEPTION 'part_price_chk FAILED';

    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
END $$;

-- CHECK: reservation quantity

DO $$
BEGIN
    BEGIN
        INSERT INTO part_reservation(
            repair_id,
            part_id,
            quantity
        )
        VALUES (1, 1, 0);

        RAISE EXCEPTION 'part_reservation_quantity_chk FAILED';

    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
END $$;

-- CHECK: payment

DO $$
BEGIN
    BEGIN
        INSERT INTO payment(
            request_id,
            amount,
            status
        )
        VALUES (1, 0, 'Оплачено');

        RAISE EXCEPTION 'payment_zero_amount_chk FAILED';

    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
END $$;

-- CHECK: notification

DO $$
BEGIN
    BEGIN
        INSERT INTO notification(
            request_id,
            event_type,
            delivery_status
        )
        VALUES (1, 'TEST', 'Неверный');

        RAISE EXCEPTION 'notification_delivery_status_chk FAILED';

    EXCEPTION WHEN check_violation THEN
        NULL;
    END;
END $$;

-- UNIQUE: payment request

INSERT INTO payment(
    request_id,
    amount,
    status
)
VALUES (1, 0, 'Не требуется');

DO $$
BEGIN
    BEGIN
        INSERT INTO payment(
            request_id,
            amount,
            status
        )
        VALUES (1, 0, 'Не требуется');

        RAISE EXCEPTION 'payment UNIQUE FAILED';

    EXCEPTION WHEN unique_violation THEN
        NULL;
    END;
END $$;

-- FK

DO $$
BEGIN
    BEGIN
        INSERT INTO equipment(
            client_id,
            type,
            manufacturer,
            model,
            status
        )
        VALUES (999, 'x', 'x', 'x', 'Зарегистрировано');

        RAISE EXCEPTION 'equipment FK FAILED';

    EXCEPTION WHEN foreign_key_violation THEN
        NULL;
    END;
END $$;

ROLLBACK;
