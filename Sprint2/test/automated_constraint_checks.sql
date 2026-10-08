-- Автоматизированная проверка схемы и ограничений
--
-- Запускать после применения миграций:
-- 001_create_base_schema.up.sql
-- 002_add_constraints_and_indexes.up.sql
--
-- Скрипт:
-- 1. Создаёт минимальные тестовые данные.
-- 2. Проверяет ограничения.
-- 3. Выводит PASS / FAIL.
-- 4. В конце делает ROLLBACK, поэтому база не изменяется.

BEGIN;


-- ============================================================
-- РЕЗУЛЬТАТЫ ТЕСТОВ
-- ============================================================

CREATE TEMP TABLE test_results (
    id SERIAL PRIMARY KEY,
    test_name TEXT NOT NULL,
    result TEXT NOT NULL,
    details TEXT
);


-- ============================================================
-- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
-- ============================================================

CREATE OR REPLACE FUNCTION pg_temp.test_rejected(
    test_name TEXT,
    sql_text TEXT
)
RETURNS void AS $$
BEGIN
    EXECUTE sql_text;

    INSERT INTO test_results(test_name, result, details)
    VALUES (
        test_name,
        'FAIL',
        'Операция была принята, хотя ожидалась ошибка'
    );

EXCEPTION
    WHEN OTHERS THEN
        INSERT INTO test_results(test_name, result, details)
        VALUES (
            test_name,
            'PASS',
            SQLSTATE || ': ' || SQLERRM
        );
END;
$$ LANGUAGE plpgsql;


CREATE OR REPLACE FUNCTION pg_temp.test_accepted(
    test_name TEXT,
    sql_text TEXT
)
RETURNS void AS $$
BEGIN
    EXECUTE sql_text;

    INSERT INTO test_results(test_name, result, details)
    VALUES (
        test_name,
        'PASS',
        'Корректные данные приняты'
    );

EXCEPTION
    WHEN OTHERS THEN
        INSERT INTO test_results(test_name, result, details)
        VALUES (
            test_name,
            'FAIL',
            SQLSTATE || ': ' || SQLERRM
        );
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- БАЗОВЫЕ ТЕСТОВЫЕ ДАННЫЕ
-- ID генерируются PostgreSQL автоматически
-- ============================================================

CREATE TEMP TABLE test_ids (
    client_id BIGINT,
    operator_id BIGINT,
    master_id BIGINT,
    master2_id BIGINT,
    equipment_id BIGINT,
    request_id BIGINT,
    work_id BIGINT,
    repair_id BIGINT,
    part_id BIGINT
);


DO $$
DECLARE
    v_client_id BIGINT;
    v_operator_id BIGINT;
    v_master_id BIGINT;
    v_master2_id BIGINT;
    v_equipment_id BIGINT;
    v_request_id BIGINT;
    v_work_id BIGINT;
    v_repair_id BIGINT;
    v_part_id BIGINT;
BEGIN

    INSERT INTO client(full_name, phone)
    VALUES ('Тестовый клиент', '+70000000000')
    RETURNING id INTO v_client_id;


    INSERT INTO employee(full_name, specialization)
    VALUES ('Тестовый оператор', 'Оператор')
    RETURNING id INTO v_operator_id;


    INSERT INTO employee(full_name, specialization)
    VALUES ('Тестовый мастер', 'Мастер')
    RETURNING id INTO v_master_id;


    INSERT INTO employee(full_name, specialization)
    VALUES ('Второй тестовый мастер', 'Мастер')
    RETURNING id INTO v_master2_id;


    INSERT INTO equipment(
        client_id,
        type,
        manufacturer,
        model,
        status
    )
    VALUES (
        v_client_id,
        'Ноутбук',
        'Test',
        'Model',
        'Зарегистрировано'
    )
    RETURNING id INTO v_equipment_id;


    INSERT INTO request(
        equipment_id,
        operator_id,
        description,
        status
    )
    VALUES (
        v_equipment_id,
        v_operator_id,
        'Тестовая заявка',
        'Принята'
    )
    RETURNING id INTO v_request_id;


    INSERT INTO work(
        request_id,
        status,
        cost
    )
    VALUES (
        v_request_id,
        'Выполняется',
        100
    )
    RETURNING id INTO v_work_id;


    INSERT INTO repair(
        work_id,
        master_id,
        description,
        cost,
        status
    )
    VALUES (
        v_work_id,
        v_master_id,
        'Тестовый ремонт',
        100,
        'Выполняется'
    )
    RETURNING id INTO v_repair_id;


    INSERT INTO part(
        name,
        article,
        price,
        stock_quantity
    )
    VALUES (
        'Тестовая деталь',
        'TEST-001',
        50,
        5
    )
    RETURNING id INTO v_part_id;


    INSERT INTO test_ids
    VALUES (
        v_client_id,
        v_operator_id,
        v_master_id,
        v_master2_id,
        v_equipment_id,
        v_request_id,
        v_work_id,
        v_repair_id,
        v_part_id
    );

END $$;


-- ============================================================
-- CHECK / NOT NULL
-- ============================================================

-- 1. Клиент должен иметь телефон или email

SELECT pg_temp.test_rejected(
    '01: client без контактов',
    'INSERT INTO client(full_name)
     VALUES (''Ошибка'')'
);


-- 2. Недопустимый статус оборудования

SELECT pg_temp.test_rejected(
    '02: equipment с неправильным status',
    format(
        'INSERT INTO equipment(
            client_id,
            type,
            manufacturer,
            model,
            status
         )
         VALUES (%s, ''x'', ''x'', ''x'', ''Ошибка'')',
        (SELECT client_id FROM test_ids)
    )
);


-- 3. Недопустимый статус заявки

SELECT pg_temp.test_rejected(
    '03: request с неправильным status',
    format(
        'INSERT INTO request(
            equipment_id,
            description,
            status
         )
         VALUES (%s, ''тест'', ''Ошибка'')',
        (SELECT equipment_id FROM test_ids)
    )
);


-- 4. Ожидание требует waiting_reason

SELECT pg_temp.test_rejected(
    '04: Ожидание без waiting_reason',
    format(
        'INSERT INTO request(
            equipment_id,
            description,
            status
         )
         VALUES (%s, ''тест'', ''Ожидание'')',
        (SELECT equipment_id FROM test_ids)
    )
);


-- 5. waiting_reason нельзя указывать для другого статуса

SELECT pg_temp.test_rejected(
    '05: waiting_reason при статусе Создана',
    format(
        'INSERT INTO request(
            equipment_id,
            description,
            status,
            waiting_reason
         )
         VALUES (%s, ''тест'', ''Создана'', ''PART_WAITING'')',
        (SELECT equipment_id FROM test_ids)
    )
);


-- 6. В ремонт нельзя переводить без согласия клиента

SELECT pg_temp.test_rejected(
    '06: В ремонте без client_approved',
    format(
        'INSERT INTO request(
            equipment_id,
            description,
            status,
            client_approved
         )
         VALUES (%s, ''тест'', ''В ремонте'', false)',
        (SELECT equipment_id FROM test_ids)
    )
);


-- 7. Отрицательная стоимость работы

SELECT pg_temp.test_rejected(
    '07: work с отрицательной стоимостью',
    format(
        'INSERT INTO work(request_id, cost)
         VALUES (%s, -1)',
        (SELECT request_id FROM test_ids)
    )
);


-- 8. Недопустимый статус ремонта

SELECT pg_temp.test_rejected(
    '08: repair с неправильным status',
    format(
        'INSERT INTO repair(
            work_id,
            master_id,
            description,
            cost,
            status
         )
         VALUES (%s, %s, ''тест'', 1, ''Ошибка'')',
        (SELECT work_id FROM test_ids),
        (SELECT master_id FROM test_ids)
    )
);


-- 9. Завершённый ремонт требует результата

SELECT pg_temp.test_rejected(
    '09: завершённый repair без результата',
    format(
        'INSERT INTO repair(
            work_id,
            master_id,
            description,
            cost,
            status
         )
         VALUES (%s, %s, ''тест'', 1, ''Завершён'')',
        (SELECT work_id FROM test_ids),
        (SELECT master_id FROM test_ids)
    )
);


-- 10. Отрицательная цена детали

SELECT pg_temp.test_rejected(
    '10: part с отрицательной ценой',
    'INSERT INTO part(name, price)
     VALUES (''Ошибка'', -1)'
);


-- 11. Нулевое количество запчасти в резерве

SELECT pg_temp.test_rejected(
    '11: reservation с quantity=0',
    format(
        'INSERT INTO part_reservation(
            repair_id,
            part_id,
            quantity
         )
         VALUES (%s, %s, 0)',
        (SELECT repair_id FROM test_ids),
        (SELECT part_id FROM test_ids)
    )
);


-- 12. Нулевая оплаченная сумма

SELECT pg_temp.test_rejected(
    '12: payment amount=0 при статусе Оплачено',
    format(
        'INSERT INTO payment(
            request_id,
            amount,
            status
         )
         VALUES (%s, 0, ''Оплачено'')',
        (SELECT request_id FROM test_ids)
    )
);


-- 13. Неправильный статус уведомления

SELECT pg_temp.test_rejected(
    '13: notification с неправильным delivery_status',
    format(
        'INSERT INTO notification(
            request_id,
            event_type,
            delivery_status
         )
         VALUES (%s, ''TEST'', ''Ошибка'')',
        (SELECT request_id FROM test_ids)
    )
);


-- ============================================================
-- UNIQUE
-- ============================================================

-- 14. Два активных мастера на одну заявку

SELECT pg_temp.test_rejected(
    '14: два активных мастера на одну заявку',
    format(
        'DO $$
         BEGIN
             INSERT INTO master_assignment(
                 request_id,
                 employee_id,
                 is_active
             )
             VALUES (%s, %s, true);

             INSERT INTO master_assignment(
                 request_id,
                 employee_id,
                 is_active
             )
             VALUES (%s, %s, true);
         END $$',
        (SELECT request_id FROM test_ids),
        (SELECT master_id FROM test_ids),
        (SELECT request_id FROM test_ids),
        (SELECT master2_id FROM test_ids)
    )
);


-- 15. Два активных резерва одной детали

SELECT pg_temp.test_rejected(
    '15: повторное активное резервирование детали',
    format(
        'DO $$
         BEGIN
             INSERT INTO part_reservation(
                 repair_id,
                 part_id,
                 quantity,
                 status
             )
             VALUES (%s, %s, 1, ''Активен'');

             INSERT INTO part_reservation(
                 repair_id,
                 part_id,
                 quantity,
                 status
             )
             VALUES (%s, %s, 1, ''Активен'');
         END $$',
        (SELECT repair_id FROM test_ids),
        (SELECT part_id FROM test_ids),
        (SELECT repair_id FROM test_ids),
        (SELECT part_id FROM test_ids)
    )
);


-- 16. Уникальный article детали

SELECT pg_temp.test_rejected(
    '16: дублирование article',
    'INSERT INTO part(
        name,
        article,
        price,
        stock_quantity
     )
     VALUES (
        ''Дубликат'',
        ''TEST-001'',
        10,
        1
     )'
);


-- 17. Одна оплата на заявку

SELECT pg_temp.test_accepted(
    '17: первая оплата заявки',
    format(
        'INSERT INTO payment(
            request_id,
            amount,
            status
         )
         VALUES (%s, 0, ''Не требуется'')',
        (SELECT request_id FROM test_ids)
    )
);


SELECT pg_temp.test_rejected(
    '18: повторная оплата заявки',
    format(
        'INSERT INTO payment(
            request_id,
            amount,
            status
         )
         VALUES (%s, 0, ''Не требуется'')',
        (SELECT request_id FROM test_ids)
    )
);


-- ============================================================
-- FOREIGN KEY
-- ============================================================

-- 19. Несуществующее оборудование

SELECT pg_temp.test_rejected(
    '19: request с несуществующим equipment',
    'INSERT INTO request(
        equipment_id,
        description
     )
     VALUES (999999, ''тест'')'
);


-- ============================================================
-- STATUS HISTORY
-- ============================================================

-- 20. old_status и new_status не должны совпадать

SELECT pg_temp.test_rejected(
    '20: одинаковые old_status и new_status',
    format(
        'INSERT INTO status_history(
            request_id,
            old_status,
            new_status
         )
         VALUES (%s, ''Принята'', ''Принята'')',
        (SELECT request_id FROM test_ids)
    )
);


-- ============================================================
-- КОРРЕКТНЫЕ ДАННЫЕ
-- ============================================================

-- 21. Обычная заявка

SELECT pg_temp.test_accepted(
    '21: корректная заявка',
    format(
        'INSERT INTO request(
            equipment_id,
            description,
            status
         )
         VALUES (%s, ''Корректная заявка'', ''Создана'')',
        (SELECT equipment_id FROM test_ids)
    )
);


-- 22. Ожидание с причиной

SELECT pg_temp.test_accepted(
    '22: Ожидание с waiting_reason',
    format(
        'INSERT INTO request(
            equipment_id,
            description,
            status,
            waiting_reason
         )
         VALUES (%s, ''Ожидание детали'', ''Ожидание'', ''PART_WAITING'')',
        (SELECT equipment_id FROM test_ids)
    )
);


-- 23. Нулевая сумма со статусом Не требуется

SELECT pg_temp.test_accepted(
    '23: payment 0 + Не требуется',
    format(
        'INSERT INTO payment(
            request_id,
            amount,
            status
         )
         VALUES (%s, 0, ''Не требуется'')',
        (SELECT request_id FROM test_ids)
    )
);


-- ============================================================
-- ИТОГ
-- ============================================================

SELECT
    test_name AS "Тест",
    result AS "Результат",
    details AS "Подробности"
FROM test_results
ORDER BY id;


DO $$
DECLARE
    total_tests INT;
    failed_tests INT;
BEGIN

    SELECT COUNT(*)
    INTO total_tests
    FROM test_results;

    SELECT COUNT(*)
    INTO failed_tests
    FROM test_results
    WHERE result = 'FAIL';

    RAISE NOTICE '----------------------------------------';
    RAISE NOTICE 'Всего тестов: %', total_tests;
    RAISE NOTICE 'Ошибок: %', failed_tests;

    IF failed_tests = 0 THEN
        RAISE NOTICE 'ВСЕ ТЕСТЫ ПРОЙДЕНЫ';
    ELSE
        RAISE WARNING 'ЕСТЬ НЕПРОЙДЕННЫЕ ТЕСТЫ';
    END IF;

END $$;


-- Скрипт ничего не изменяет в базе.
ROLLBACK;
