#!/bin/bash
set -e

: "${PATRONI_NAME:?PATRONI_NAME is required}"
: "${POSTGRES_ADMIN_USER:?POSTGRES_ADMIN_USER is required}"
: "${POSTGRES_ADMIN_PASSWORD:?POSTGRES_ADMIN_PASSWORD is required}"
: "${REPLICATION_USER:?REPLICATION_USER is required}"
: "${REPLICATION_PASSWORD:?REPLICATION_PASSWORD is required}"

PATRONI_CONFIG=/etc/patroni/patroni.yml

envsubst \
  '${PATRONI_NAME} ${POSTGRES_ADMIN_USER} ${POSTGRES_ADMIN_PASSWORD} ${REPLICATION_USER} ${REPLICATION_PASSWORD} ${APPLICATION_USER} ${APPLICATION_PASSWORD} ${ANALYST_USER} ${ANALYST_PASSWORD}' \
  < /etc/patroni/patroni.yml.tmpl \
  > "$PATRONI_CONFIG"

chown root:postgres "$PATRONI_CONFIG"
chmod 640 "$PATRONI_CONFIG"
chown -R postgres:postgres "$PGDATA"
chmod 700 "$PGDATA"

exec gosu postgres patroni "$PATRONI_CONFIG"
