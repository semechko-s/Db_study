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

echo "Creating database: ${POSTGRES_DB}"

createdb \
    --maintenance-db="$CONNECTION_URL" \
    --owner="$POSTGRES_ADMIN_USER" \
    "$POSTGRES_DB"

export PGHOST=127.0.0.1
export PGPORT=5432
export PGPASSWORD="$POSTGRES_ADMIN_PASSWORD"

echo "Initializing PostgreSQL roles and schemas..."

/course/init/01-initialize-cluster.sh

echo "Applying project migrations..."

/course/init/02-apply-project-migrations.sh

echo "Post-bootstrap initialization completed."
