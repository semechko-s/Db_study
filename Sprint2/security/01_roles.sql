
-- Запускать от имени администратора PostgreSQL, имеющего право создавать и изменять роли
-- Пароли здесь не задаются

-- Создание ролей при отсутствии
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'service_admin'
    ) THEN
        CREATE ROLE service_admin;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'service_app'
    ) THEN
        CREATE ROLE service_app;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'service_analyst'
    ) THEN
        CREATE ROLE service_analyst;
    END IF;
END
$$;

-- Настройка параметров ролей

ALTER ROLE service_admin
    WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
    NOREPLICATION INHERIT;

ALTER ROLE service_app
    WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
    NOREPLICATION INHERIT;

ALTER ROLE service_analyst
    WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE
    NOREPLICATION INHERIT;

-- Запрет опасных административных прав приложению CREATE на схему public приложению не предоставляем

REVOKE CREATE ON SCHEMA public FROM service_app;
REVOKE CREATE ON SCHEMA public FROM service_analyst;

-- Подключение к бд

GRANT CONNECT ON DATABASE service_center
    TO service_admin, service_app, service_analyst;

-- Доступ к схеме public

GRANT USAGE ON SCHEMA public
    TO service_app, service_analyst, service_admin;

-- Администратор проекта может создавать объекты в public
GRANT CREATE ON SCHEMA public TO service_admin;

-- Права приложения на существующие таблицы

REVOKE ALL PRIVILEGES
    ON ALL TABLES IN SCHEMA public
    FROM service_app;

GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA public
    TO service_app;

-- Права приложения на существующие последовательности

REVOKE ALL PRIVILEGES
    ON ALL SEQUENCES IN SCHEMA public
    FROM service_app;

GRANT USAGE, SELECT
    ON ALL SEQUENCES IN SCHEMA public
    TO service_app;

-- Права аналитика на существующие таблицы

REVOKE ALL PRIVILEGES
    ON ALL TABLES IN SCHEMA public
    FROM service_analyst;

GRANT SELECT
    ON ALL TABLES IN SCHEMA public
    TO service_analyst;

-- Аналитику не нужны права на последовательности
REVOKE ALL PRIVILEGES
    ON ALL SEQUENCES IN SCHEMA public
    FROM service_analyst;

-- Права административной роли проекта

GRANT ALL PRIVILEGES
    ON ALL TABLES IN SCHEMA public
    TO service_admin;

GRANT ALL PRIVILEGES
    ON ALL SEQUENCES IN SCHEMA public
    TO service_admin;

-- ВАЖНО: Права на будущие таблицы и последовательности настраиваются отдельно для фактической роли, создающей объекты миграций.

-- Проверка параметров ролей

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
)
ORDER BY rolname;

-- Проверка доступа приложения к схеме

SELECT
    has_database_privilege(
        'service_app', 'service_center', 'CONNECT'
    ) AS app_can_connect,
    has_schema_privilege(
        'service_app', 'public', 'USAGE'
    ) AS app_can_use_schema,
    has_schema_privilege(
        'service_app', 'public', 'CREATE'
    ) AS app_can_create_objects;
