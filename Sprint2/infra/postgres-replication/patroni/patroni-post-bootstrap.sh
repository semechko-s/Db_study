#!/bin/bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: patroni-post-bootstrap.sh CONNECTION_URL" >&2
    exit 1
fi

CONNECTION_URL="$1"

: "${POSTGRES_DB:?POSTGRES_DB is required}"
: "${POSTGRES_ADMIN_USER:?POSTGRES_ADMIN_USER is required}"
: "${REPLICATION_USER:?REPLICATION_USER is required}"
: "${REPLICATION_PASSWORD:?REPLICATION_PASSWORD is required}"
: "${APPLICATION_USER:?APPLICATION_USER is required}"
: "${APPLICATION_PASSWORD:?APPLICATION_PASSWORD is required}"
: "${ANALYST_USER:?ANALYST_USER is required}"
: "${ANALYST_PASSWORD:?ANALYST_PASSWORD is required}"

echo "Creating PostgreSQL roles..."

psql \
    --dbname="$CONNECTION_URL" \
    --set=ON_ERROR_STOP=1 \
    --set=replication_user="$REPLICATION_USER" \
    --set=replication_password="$REPLICATION_PASSWORD" \
    --set=application_user="$APPLICATION_USER" \
    --set=application_password="$APPLICATION_PASSWORD" \
    --set=analyst_user="$ANALYST_USER" \
    --set=analyst_password="$ANALYST_PASSWORD" <<'SQL'

SELECT format('CREATE ROLE %I WITH LOGIN REPLICATION PASSWORD %L',
              :'replication_user', :'replication_password')
\gexec

SELECT format('CREATE ROLE %I WITH LOGIN PASSWORD %L',
              :'application_user', :'application_password')
\gexec

SELECT format('CREATE ROLE %I WITH LOGIN PASSWORD %L',
              :'analyst_user', :'analyst_password')
\gexec

SQL

echo "Creating database: ${POSTGRES_DB}"

createdb \
    --maintenance-db="$CONNECTION_URL" \
    --owner="$POSTGRES_ADMIN_USER" \
    "$POSTGRES_DB"

echo "Post-bootstrap initialization completed."
