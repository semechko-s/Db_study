-- Автоматический тест ролей и RLS-политики. Запускать от суперпользователя после 01_roles.sql и 03_rls_policy.sql:
-- psql -U postgres -d service_center -f security/04_rls_test.sql

\set ON_ERROR_STOP on
\pset pager off

BEGIN;

-- Таблицы результатов и тестовых идентификаторов
CREATE TEMP TABLE rls_test_results (
    n         serial,
    test_name text,
    expected  text,
    actual    text,
    details   text
);

CREATE TEMP TABLE rls_test_ids (
    kind text PRIMARY KEY,
    id   bigint NOT NULL
);

-- Функция проверки SELECT-запросов от имени заданной роли

CREATE FUNCTION pg_temp.check_rls(
    p_role text,
    p_test_name text,
    p_sql text,
    p_expected text
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_actual  text;
    v_details text := '';
BEGIN
    BEGIN
        EXECUTE format('SET LOCAL ROLE %I', p_role);
        EXECUTE p_sql INTO v_actual;

    EXCEPTION
        WHEN insufficient_privilege THEN
            v_actual := 'ЗАПРЕЩЕНО';
            v_details := SQLERRM;

        WHEN OTHERS THEN
            v_actual := 'ОШИБКА';
            v_details := SQLSTATE || ': ' || SQLERRM;
    END;

    RESET ROLE;

    INSERT INTO rls_test_results
        (test_name, expected, actual, details)
    VALUES
        (p_test_name, p_expected, v_actual, v_details);
END;
$$;

-- Функция проверки команд, не возвращающих строки

CREATE FUNCTION pg_temp.check_command(
    p_role text,
    p_test_name text,
    p_sql text,
    p_expected text
) RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
    v_actual  text;
    v_details text := '';
BEGIN
    BEGIN
        EXECUTE format('SET LOCAL ROLE %I', p_role);
        EXECUTE p_sql;

        v_actual := 'РАЗРЕШЕНО';

    EXCEPTION
        WHEN insufficient_privilege THEN
            v_actual := 'ЗАПРЕЩЕНО';
            v_details := SQLERRM;

        WHEN OTHERS THEN
            v_actual := 'ОШИБКА';
            v_details := SQLSTATE || ': ' || SQLERRM;
    END;

    RESET ROLE;

    INSERT INTO rls_test_results
        (test_name, expected, actual, details)
    VALUES
        (p_test_name, p_expected, v_actual, v_details);
END;
$$;

-- Подготовка тестовых данных. Все ID генерируются базой данных автоматически.

-- Клиент
WITH new_client AS (
    INSERT INTO public.client (full_name, phone)
    VALUES (
        'RLS тестовый клиент',
        '+70000000900'
    )
    RETURNING id
)
INSERT INTO rls_test_ids (kind, id)
SELECT 'client', id
FROM new_client;

-- Оборудование
WITH new_equipment AS (
    INSERT INTO public.equipment (
        client_id,
        type,
        manufacturer,
        model,
        status
    )
    SELECT
        id,
        'Принтер',
        'Test',
        'RLS',
        'Выдано'
    FROM rls_test_ids
    WHERE kind = 'client'
    RETURNING id
)
INSERT INTO rls_test_ids (kind, id)
SELECT 'equipment', id
FROM new_equipment;

-- Закрытая заявка. Учитываем ограничения:
-- request_closed_requires_issued_chk: status = 'Закрыта' требует issued_at IS NOT NULL.
-- request_repair_requires_approval_chk: для статуса 'Закрыта' требуется client_approved = TRUE.
-- request_approval_at_chk: client_approved = TRUE требует approval_at IS NOT NULL.

WITH new_request AS (
    INSERT INTO public.request (
        equipment_id,
        description,
        status,
        client_approved,
        approval_at,
        issued_at
    )
    SELECT
        id,
        'Закрытая заявка для RLS-теста',
        'Закрыта',
        TRUE,
        CURRENT_TIMESTAMP,
        CURRENT_TIMESTAMP
    FROM rls_test_ids
    WHERE kind = 'equipment'
    RETURNING id
)
INSERT INTO rls_test_ids (kind, id)
SELECT 'closed_request', id
FROM new_request;

-- Незакрытая заявка
WITH new_request AS (
    INSERT INTO public.request (
        equipment_id,
        description,
        status
    )
    SELECT
        id,
        'Незакрытая заявка для RLS-теста',
        'Создана'
    FROM rls_test_ids
    WHERE kind = 'equipment'
    RETURNING id
)
INSERT INTO rls_test_ids (kind, id)
SELECT 'open_request', id
FROM new_request;

-- Проверки RLS для service_analyst. Аналитик должен видеть только закрытые заявки.

SELECT pg_temp.check_rls(
    'service_analyst',
    'RLS: аналитик видит закрытую заявку',
    format(
        'SELECT count(*)::text
         FROM public.request
         WHERE id = %s',
        (SELECT id
         FROM rls_test_ids
         WHERE kind = 'closed_request')
    ),
    '1'
);

SELECT pg_temp.check_rls(
    'service_analyst',
    'RLS: аналитик не видит незакрытую заявку',
    format(
        'SELECT count(*)::text
         FROM public.request
         WHERE id = %s',
        (SELECT id
         FROM rls_test_ids
         WHERE kind = 'open_request')
    ),
    '0'
);

-- Проверки RLS для service_app и service_admin. Обе роли должны видеть обе заявки.

SELECT pg_temp.check_rls(
    'service_app',
    'RLS: приложение видит обе заявки',
    format(
        'SELECT count(*)::text
         FROM public.request
         WHERE id IN (%s, %s)',
        (SELECT id
         FROM rls_test_ids
         WHERE kind = 'closed_request'),
        (SELECT id
         FROM rls_test_ids
         WHERE kind = 'open_request')
    ),
    '2'
);

SELECT pg_temp.check_rls(
    'service_admin',
    'RLS: администратор видит обе заявки',
    format(
        'SELECT count(*)::text
         FROM public.request
         WHERE id IN (%s, %s)',
        (SELECT id
         FROM rls_test_ids
         WHERE kind = 'closed_request'),
        (SELECT id
         FROM rls_test_ids
         WHERE kind = 'open_request')
    ),
    '2'
);

-- Контрольная проверка прав роли service_app. Приложение не должно создавать таблицы в public.

SELECT pg_temp.check_command(
    'service_app',
    'Роли: service_app не может создавать таблицы в public',
    'CREATE TABLE public.rls_test_forbidden (id bigint)',
    'ЗАПРЕЩЕНО'
);

-- Итоги тестирования

\echo
\echo '=== Результаты RLS-теста ==='

SELECT
    test_name AS "Тест",
    expected AS "Ожидалось",
    actual AS "Получено",
    CASE
        WHEN expected = actual THEN 'OK'
        ELSE '<<< НЕСООТВЕТСТВИЕ'
    END AS "Вердикт",
    details AS "Сообщение сервера"
FROM rls_test_results
ORDER BY n;

\echo
\echo '=== Сводка ==='

SELECT
    count(*) AS "Всего проверок",
    count(*) FILTER (
        WHERE expected = actual
    ) AS "Совпало",
    count(*) FILTER (
        WHERE expected <> actual
    ) AS "Несоответствий"
FROM rls_test_results;

ROLLBACK;