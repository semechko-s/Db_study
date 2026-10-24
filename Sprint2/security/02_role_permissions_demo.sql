-- Демонстрация разрешённых и запрещённых операций по ролям.
-- Запуск от суперпользователя (нужен SET ROLE; пароли ролей не нужны):
--   psql -U postgres -d service_center -f security/02_role_permissions_demo.sql

\set ON_ERROR_STOP on
\pset pager off

BEGIN;

CREATE TEMP TABLE sec_demo_results (
    n          serial,
    role_name  text,
    operation  text,
    expected   text,
    actual     text,
    details    text
);

-- Выполняет p_sql от имени p_role. Отказ в правах (42501) = ЗАПРЕЩЕНО,
-- любая другая ошибка выводится отдельно.
CREATE FUNCTION pg_temp.check_op(
    p_role text, p_operation text, p_sql text, p_expected text
) RETURNS void LANGUAGE plpgsql AS $$
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
            v_actual  := 'ЗАПРЕЩЕНО';
            v_details := SQLERRM;
        WHEN OTHERS THEN
            v_actual  := 'ОШИБКА (не права)';
            v_details := SQLSTATE || ': ' || SQLERRM;
    END;
    RESET ROLE;
    INSERT INTO sec_demo_results (role_name, operation, expected, actual, details)
    VALUES (p_role, p_operation, p_expected, v_actual, v_details);
END
$$;

\o /dev/null
-- ---------- service_app ----------
SELECT pg_temp.check_op('service_app', 'SELECT из client',
    'SELECT count(*) FROM public.client', 'РАЗРЕШЕНО');
SELECT pg_temp.check_op('service_app', 'INSERT в client',
    $q$INSERT INTO public.client (full_name, phone) VALUES ('__sec_demo__', '+70000000000')$q$, 'РАЗРЕШЕНО');
SELECT pg_temp.check_op('service_app', 'UPDATE client',
    $q$UPDATE public.client SET phone = phone WHERE full_name = '__sec_demo__'$q$, 'РАЗРЕШЕНО');
SELECT pg_temp.check_op('service_app', 'DELETE из client',
    $q$DELETE FROM public.client WHERE full_name = '__sec_demo__'$q$, 'РАЗРЕШЕНО');
SELECT pg_temp.check_op('service_app', 'CREATE TABLE в public',
    'CREATE TABLE public.sec_demo_forbidden (id bigint)', 'ЗАПРЕЩЕНО');
SELECT pg_temp.check_op('service_app', 'ALTER TABLE client',
    'ALTER TABLE public.client ADD COLUMN sec_demo_col int', 'ЗАПРЕЩЕНО');
SELECT pg_temp.check_op('service_app', 'DROP TABLE client',
    'DROP TABLE public.client', 'ЗАПРЕЩЕНО');
SELECT pg_temp.check_op('service_app', 'TRUNCATE client',
    'TRUNCATE public.client', 'ЗАПРЕЩЕНО');
SELECT pg_temp.check_op('service_app', 'GRANT роли другой роли',
    'GRANT service_admin TO service_analyst', 'ЗАПРЕЩЕНО');
SELECT pg_temp.check_op('service_app', 'CREATE ROLE',
    'CREATE ROLE sec_demo_role', 'ЗАПРЕЩЕНО');
SELECT pg_temp.check_op('service_app', 'Чтение pg_authid (хеши паролей)',
    'SELECT rolpassword FROM pg_catalog.pg_authid LIMIT 1', 'ЗАПРЕЩЕНО');

-- ---------- service_analyst ----------
SELECT pg_temp.check_op('service_analyst', 'SELECT из client',
    'SELECT count(*) FROM public.client', 'РАЗРЕШЕНО');
SELECT pg_temp.check_op('service_analyst', 'SELECT из request',
    'SELECT count(*) FROM public.request', 'РАЗРЕШЕНО');
SELECT pg_temp.check_op('service_analyst', 'INSERT в client',
    $q$INSERT INTO public.client (full_name, phone) VALUES ('__sec_demo__', '+70000000000')$q$, 'ЗАПРЕЩЕНО');
SELECT pg_temp.check_op('service_analyst', 'UPDATE client',
    $q$UPDATE public.client SET phone = phone WHERE full_name = '__sec_demo__'$q$, 'ЗАПРЕЩЕНО');
SELECT pg_temp.check_op('service_analyst', 'DELETE из client',
    $q$DELETE FROM public.client WHERE full_name = '__sec_demo__'$q$, 'ЗАПРЕЩЕНО');
SELECT pg_temp.check_op('service_analyst', 'TRUNCATE client',
    'TRUNCATE public.client', 'ЗАПРЕЩЕНО');
SELECT pg_temp.check_op('service_analyst', 'CREATE TABLE в public',
    'CREATE TABLE public.sec_demo_forbidden (id bigint)', 'ЗАПРЕЩЕНО');
SELECT pg_temp.check_op('service_analyst', 'DROP TABLE client',
    'DROP TABLE public.client', 'ЗАПРЕЩЕНО');
SELECT pg_temp.check_op('service_analyst', 'CREATE ROLE',
    'CREATE ROLE sec_demo_role', 'ЗАПРЕЩЕНО');

-- ---------- service_admin ----------
SELECT pg_temp.check_op('service_admin', 'SELECT из client',
    'SELECT count(*) FROM public.client', 'РАЗРЕШЕНО');
SELECT pg_temp.check_op('service_admin', 'INSERT в client',
    $q$INSERT INTO public.client (full_name, phone) VALUES ('__sec_demo__', '+70000000000')$q$, 'РАЗРЕШЕНО');
SELECT pg_temp.check_op('service_admin', 'UPDATE client',
    $q$UPDATE public.client SET phone = phone WHERE full_name = '__sec_demo__'$q$, 'РАЗРЕШЕНО');
SELECT pg_temp.check_op('service_admin', 'DELETE из client',
    $q$DELETE FROM public.client WHERE full_name = '__sec_demo__'$q$, 'РАЗРЕШЕНО');
SELECT pg_temp.check_op('service_admin', 'CREATE TABLE в public',
    'CREATE TABLE public.sec_demo_admin_tmp (id bigint)', 'РАЗРЕШЕНО');
SELECT pg_temp.check_op('service_admin', 'TRUNCATE своей таблицы',
    'TRUNCATE public.sec_demo_admin_tmp', 'РАЗРЕШЕНО');
SELECT pg_temp.check_op('service_admin', 'DROP своей таблицы',
    'DROP TABLE public.sec_demo_admin_tmp', 'РАЗРЕШЕНО');
SELECT pg_temp.check_op('service_admin', 'CREATE ROLE',
    'CREATE ROLE sec_demo_role', 'ЗАПРЕЩЕНО');
SELECT pg_temp.check_op('service_admin', 'Чтение pg_authid (хеши паролей)',
    'SELECT rolpassword FROM pg_catalog.pg_authid LIMIT 1', 'ЗАПРЕЩЕНО');
\o
-- ---------- Итог ----------
\echo
\echo '=== Результаты проверки прав ==='
SELECT
    role_name AS "Роль",
    operation AS "Операция",
    expected  AS "Ожидалось",
    actual    AS "Получено",
    CASE WHEN expected = actual THEN 'OK' ELSE '<<< НЕСООТВЕТСТВИЕ' END AS "Вердикт",
    details   AS "Сообщение сервера"
FROM sec_demo_results
ORDER BY n;

\echo
\echo '=== Сводка ==='
SELECT
    count(*)                                   AS "Всего проверок",
    count(*) FILTER (WHERE expected = actual)  AS "Совпало",
    count(*) FILTER (WHERE expected <> actual) AS "Несоответствий"
FROM sec_demo_results;

\echo
\echo '=== Атрибуты ролей ==='
SELECT rolname, rolcanlogin, rolsuper, rolcreatedb, rolcreaterole, rolreplication
FROM pg_roles
WHERE rolname IN ('service_admin', 'service_app', 'service_analyst')
ORDER BY rolname;

ROLLBACK;