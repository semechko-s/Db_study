#!/bin/sh
set -eu

: "${POSTGRES_DB:?POSTGRES_DB is required}"
: "${POSTGRES_ADMIN_USER:?POSTGRES_ADMIN_USER is required}"
: "${REPLICATION_USER:?REPLICATION_USER is required}"
: "${REPLICATION_PASSWORD:?REPLICATION_PASSWORD is required}"
: "${APPLICATION_USER:?APPLICATION_USER is required}"
: "${APPLICATION_PASSWORD:?APPLICATION_PASSWORD is required}"
: "${ANALYST_USER:?ANALYST_USER is required}"
: "${ANALYST_PASSWORD:?ANALYST_PASSWORD is required}"

psql \
  --username "$POSTGRES_ADMIN_USER" \
  --dbname "$POSTGRES_DB" \
  --set=ON_ERROR_STOP=1 \
  --set=database_name="$POSTGRES_DB" \
  --set=admin_user="$POSTGRES_ADMIN_USER" \
  --set=replication_user="$REPLICATION_USER" \
  --set=replication_password="$REPLICATION_PASSWORD" \
  --set=application_user="$APPLICATION_USER" \
  --set=application_password="$APPLICATION_PASSWORD" \
  --set=analyst_user="$ANALYST_USER" \
  --set=analyst_password="$ANALYST_PASSWORD" <<'SQL'

-- Создание и настройка роли репликации
SELECT format('CREATE ROLE %I', :'replication_user')
WHERE NOT EXISTS (
  SELECT 1 FROM pg_roles WHERE rolname = :'replication_user'
) \gexec

SELECT format(
  'ALTER ROLE %I WITH LOGIN REPLICATION NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD %L',
  :'replication_user',
  :'replication_password'
) \gexec

-- Создание и настройка роли приложения
SELECT format('CREATE ROLE %I', :'application_user')
WHERE NOT EXISTS (
  SELECT 1 FROM pg_roles WHERE rolname = :'application_user'
) \gexec

SELECT format(
  'ALTER ROLE %I WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD %L',
  :'application_user',
  :'application_password'
) \gexec

-- Создание и настройка роли аналитика
SELECT format('CREATE ROLE %I', :'analyst_user')
WHERE NOT EXISTS (
  SELECT 1 FROM pg_roles WHERE rolname = :'analyst_user'
) \gexec

SELECT format(
  'ALTER ROLE %I WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION PASSWORD %L',
  :'analyst_user',
  :'analyst_password'
) \gexec

-- Настройка схем
REVOKE CREATE ON SCHEMA public FROM PUBLIC;

CREATE SCHEMA IF NOT EXISTS app AUTHORIZATION :"admin_user";
REVOKE ALL ON SCHEMA app FROM PUBLIC;

-- Служебная таблица проверки репликации
CREATE TABLE IF NOT EXISTS app.replication_probe (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  marker text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT clock_timestamp()
);

-- Доступ к базе данных
GRANT CONNECT ON DATABASE :"database_name"
TO :"application_user", :"analyst_user";

GRANT USAGE ON SCHEMA public
TO :"application_user", :"analyst_user";

-- Существующие таблицы проекта
GRANT SELECT, INSERT, UPDATE, DELETE
ON ALL TABLES IN SCHEMA public
TO :"application_user";

GRANT SELECT
ON ALL TABLES IN SCHEMA public
TO :"analyst_user";

-- Существующие последовательности
GRANT USAGE, SELECT, UPDATE
ON ALL SEQUENCES IN SCHEMA public
TO :"application_user";

-- Права по умолчанию для будущих таблиц
-- Миграции выполняются от имени admin_user
ALTER DEFAULT PRIVILEGES FOR ROLE :"admin_user" IN SCHEMA public
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"application_user";

ALTER DEFAULT PRIVILEGES FOR ROLE :"admin_user" IN SCHEMA public
GRANT SELECT ON TABLES TO :"analyst_user";

ALTER DEFAULT PRIVILEGES FOR ROLE :"admin_user" IN SCHEMA public
GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO :"application_user";

-- =====================================================
-- Права на служебную схему app
-- =====================================================

GRANT USAGE ON SCHEMA app
TO :"application_user", :"analyst_user";

GRANT SELECT, INSERT, UPDATE, DELETE
ON ALL TABLES IN SCHEMA app
TO :"application_user";

GRANT USAGE, SELECT
ON ALL SEQUENCES IN SCHEMA app
TO :"application_user";

GRANT SELECT
ON ALL TABLES IN SCHEMA app
TO :"analyst_user";

ALTER DEFAULT PRIVILEGES FOR ROLE :"admin_user" IN SCHEMA app
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"application_user";

ALTER DEFAULT PRIVILEGES FOR ROLE :"admin_user" IN SCHEMA app
GRANT USAGE, SELECT ON SEQUENCES TO :"application_user";

ALTER DEFAULT PRIVILEGES FOR ROLE :"admin_user" IN SCHEMA app
GRANT SELECT ON TABLES TO :"analyst_user";

SQL