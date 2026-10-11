DO $$
DECLARE
    v_client_id BIGINT;
    v_employee_id BIGINT;
    v_equipment_id BIGINT;
    v_request_id BIGINT;
    v_work_id BIGINT;
    v_part_id BIGINT;
    v_repair_a_id BIGINT;
    v_repair_b_id BIGINT;
BEGIN
    -- Тестовый клиент.
    SELECT id INTO v_client_id
    FROM client
    WHERE phone = '+70000000909'
    LIMIT 1;

    IF v_client_id IS NULL THEN
        INSERT INTO client (full_name, phone)
        VALUES ('BR09 Тестовый клиент', '+70000000909')
        RETURNING id INTO v_client_id;
    END IF;

    -- Тестовый мастер.
    SELECT id INTO v_employee_id
    FROM employee
    WHERE full_name = 'BR09 Тестовый мастер'
    LIMIT 1;

    IF v_employee_id IS NULL THEN
        INSERT INTO employee (full_name, specialization)
        VALUES ('BR09 Тестовый мастер', 'Мастер')
        RETURNING id INTO v_employee_id;
    END IF;

    -- Тестовое устройство.
    SELECT id INTO v_equipment_id
    FROM equipment
    WHERE serial_number = 'BR09-CONCURRENCY-DEVICE';

    IF v_equipment_id IS NULL THEN
        INSERT INTO equipment
            (client_id, type, manufacturer, model, serial_number, status)
        VALUES
            (v_client_id, 'Тестовое устройство', 'BR09',
             'Concurrency', 'BR09-CONCURRENCY-DEVICE', 'Зарегистрировано')
        RETURNING id INTO v_equipment_id;
    END IF;

    -- Заявка.
    SELECT id INTO v_request_id
    FROM request
    WHERE description = 'BR09 тестовая заявка'
    LIMIT 1;

    IF v_request_id IS NULL THEN
        INSERT INTO request (equipment_id, description, status)
        VALUES (v_equipment_id, 'BR09 тестовая заявка', 'Принята')
        RETURNING id INTO v_request_id;
    END IF;

    -- Работа.
    SELECT id INTO v_work_id
    FROM work
    WHERE request_id = v_request_id
    LIMIT 1;

    IF v_work_id IS NULL THEN
        INSERT INTO work (request_id, status, cost)
        VALUES (v_request_id, 'Выполняется', 100)
        RETURNING id INTO v_work_id;
    END IF;

    -- Запчасть с остатком ровно в одну единицу.
    SELECT id INTO v_part_id
    FROM part
    WHERE article = 'BR09-CONCURRENCY-TEST'
    ORDER BY id
    LIMIT 1;

    IF v_part_id IS NULL THEN
        INSERT INTO part (name, article, price, stock_quantity)
        VALUES ('Тестовая запчасть BR09',
                'BR09-CONCURRENCY-TEST', 100, 1)
        RETURNING id INTO v_part_id;
    ELSE
        UPDATE part
        SET stock_quantity = 1
        WHERE id = v_part_id;
    END IF;

    -- Два разных ремонта.
    SELECT id INTO v_repair_a_id
    FROM repair
    WHERE description = 'BR09 ремонт A'
    LIMIT 1;

    IF v_repair_a_id IS NULL THEN
        INSERT INTO repair (work_id, master_id, description, cost, status)
        VALUES (v_work_id, v_employee_id, 'BR09 ремонт A', 100, 'Выполняется')
        RETURNING id INTO v_repair_a_id;
    END IF;

    SELECT id INTO v_repair_b_id
    FROM repair
    WHERE description = 'BR09 ремонт B'
    LIMIT 1;

    IF v_repair_b_id IS NULL THEN
        INSERT INTO repair (work_id, master_id, description, cost, status)
        VALUES (v_work_id, v_employee_id, 'BR09 ремонт B', 100, 'Выполняется')
        RETURNING id INTO v_repair_b_id;
    END IF;

    RAISE NOTICE 'PART_ID=%, REPAIR_A_ID=%, REPAIR_B_ID=%',
        v_part_id, v_repair_a_id, v_repair_b_id;
END $$;

SELECT id, article, stock_quantity
FROM part
WHERE article = 'BR09-CONCURRENCY-TEST';

SELECT id, description
FROM repair
WHERE description IN ('BR09 ремонт A', 'BR09 ремонт B')
ORDER BY description;