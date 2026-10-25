-- Автоматический тест: набор ролей + политика RLS из 03_rls_policy.sql.
-- Запускать от суперпользователя после 01_roles.sql и 03_rls_policy.sql:
--   psql -U postgres -d service_center -f security/04_rls_test.sql
--
-- Этот файл не повторяет весь набор проверок прав ролей — они уже
-- полностью покрыты в security/02_role_permissions_demo.sql (Аня).
-- Здесь — только то, чего там не было: проверка самой RLS-политики
-- из 03_rls_policy.sql, плюс один контрольный тест на роли для
-- полноты формулировки пункта "тест набора ролей и политик RLS".

\set ON_ERROR_STOP on
\pset pager off

BEGIN;

CREATE TEMP TABLE rls_test_results (
    n        serial,
    test_name text,
    expected  text,
    actual    text,
    details   text
);

-- Выполняет p_sql от имени p_role и сравнивает результат с ожидаемым.
CREATE FUNCTION pg_temp.check_rls(
    p_role text, p_test_name text, p_sql text, p_expected text
) RETURNS void LANGUAGE plpgsql AS $$
DECLARE
    v_actual  text;
    v_details text := '';
BEGIN
    BEGIN
        EXECUTE format('SET LOCAL ROLE %I', p_role);
        EXECUTE p_sql INTO v_actual;
    EXCEPTION
        WHEN insufficient_privilege THEN
            v_actual  := 'ЗАПРЕЩЕНО';
            v_details := SQLERRM;
        WHEN OTHERS THEN
            v_actual  := 'ОШИБКА';
            v_details := SQLSTATE || ': ' || SQLERRM;
    END;
    RESET ROLE;
    INSERT INTO rls_test_results (test_name, expected, actual, details)
    VALUES (p_test_name, p_expected, v_actual, v_details);
END
$$;

-- ------------------------------------------------------------
-- Подготовка тестовых данных (от имени service_admin — ему разрешено
-- всё в таблице request согласно политике admin_app_full_access).
-- Одна заявка закрыта, одна ещё в работе.
-- ------------------------------------------------------------

INSERT INTO client (id, full_name, phone)
OVERRIDING SYSTEM VALUE
VALUES (900, 'RLS тестовый клиент', '+70000000900');

INSERT INTO equipment (id, client_id, type, manufacturer, model, status)
OVERRIDING SYSTEM VALUE
VALUES (900, 900, 'Принтер', 'Test', 'RLS', 'Выдано');

INSERT INTO request (id, equipment_id, description, status)
OVERRIDING SYSTEM VALUE
VALUES (900, 900, 'Закрытая заявка для RLS-теста', 'Закрыта');

INSERT INTO request (id, equipment_id, description, status)
OVERRIDING SYSTEM VALUE
VALUES (901, 900, 'Незакрытая заявка для RLS-теста', 'Создана');

-- ------------------------------------------------------------
-- RLS: аналитик должен видеть только закрытую заявку (id=900),
-- а не открытую (id=901).
-- ------------------------------------------------------------

SELECT pg_temp.check_rls(
    'service_analyst',
    'RLS: аналитик видит закрытую заявку',
    'SELECT count(*)::text FROM public.request WHERE id = 900',
    '1'
);

SELECT pg_temp.check_rls(
    'service_analyst',
    'RLS: аналитик НЕ видит незакрытую заявку',
    'SELECT count(*)::text FROM public.request WHERE id = 901',
    '0'
);

-- ------------------------------------------------------------
-- RLS: приложение и администратор должны видеть обе заявки,
-- RLS не должен мешать их обычной работе.
-- ------------------------------------------------------------

SELECT pg_temp.check_rls(
    'service_app',
    'RLS: приложение видит обе заявки (900 и 901)',
    'SELECT count(*)::text FROM public.request WHERE id IN (900, 901)',
    '2'
);

SELECT pg_temp.check_rls(
    'service_admin',
    'RLS: администратор видит обе заявки (900 и 901)',
    'SELECT count(*)::text FROM public.request WHERE id IN (900, 901)',
    '2'
);

-- ------------------------------------------------------------
-- Один контрольный тест на роли (для полноты пункта "роли и RLS";
-- полный набор таких тестов — в security/02_role_permissions_demo.sql).
-- ------------------------------------------------------------

SELECT pg_temp.check_rls(
    'service_app',
    'Роли: service_app не может создавать таблицы в public',
    'CREATE TABLE public.rls_test_forbidden (id bigint); SELECT ''создано''',
    'ЗАПРЕЩЕНО'
);

-- ------------------------------------------------------------
-- Итог
-- ------------------------------------------------------------

\echo
\echo '=== Результаты RLS-теста ==='
SELECT
    test_name AS "Тест",
    expected  AS "Ожидалось",
    actual    AS "Получено",
    CASE WHEN expected = actual THEN 'OK' ELSE '<<< НЕСООТВЕТСТВИЕ' END AS "Вердикт",
    details   AS "Сообщение сервера"
FROM rls_test_results
ORDER BY n;

\echo
\echo '=== Сводка ==='
SELECT
    count(*)                                   AS "Всего проверок",
    count(*) FILTER (WHERE expected = actual)  AS "Совпало",
    count(*) FILTER (WHERE expected <> actual) AS "Несоответствий"
FROM rls_test_results;

-- Ничего не остаётся в базе: и тестовые данные, и сама политика
-- (политика создаётся отдельным файлом 03_rls_policy.sql и не входит
-- в эту транзакцию) — откатываются только INSERT'ы данного теста.
ROLLBACK;
