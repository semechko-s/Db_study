-- Вывод ролей и их прав

SELECT
    rolname,
    rolcanlogin,
    rolsuper,
    rolcreatedb,
    rolcreaterole,
    rolreplication
FROM pg_roles
WHERE rolname IN (
    'service_admin',
    'service_app',
    'service_analyst'
);
SELECT
    has_database_privilege(
        'service_app',
        'service_center',
        'CONNECT'
    ) AS can_connect,
    has_schema_privilege(
        'service_app',
        'public',
        'CREATE'
    ) AS can_create_in_schema;


-- Запустить внутри базы service_center.
-- Проверки выполняются в транзакции.

BEGIN;

SET LOCAL ROLE service_app;

-- Должно успешно выполниться:
SELECT COUNT(*) FROM public.client;

-- Должно завершиться ошибкой недостатка прав:
CREATE TABLE public.forbidden_test (
    id BIGINT PRIMARY KEY
);

ROLLBACK;
