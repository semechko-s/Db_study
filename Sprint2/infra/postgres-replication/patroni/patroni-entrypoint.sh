#!/bin/bash
set -e

: "${PATRONI_NAME:?PATRONI_NAME is required}"
: "${POSTGRES_ADMIN_USER:?POSTGRES_ADMIN_USER is required}"
: "${POSTGRES_ADMIN_PASSWORD:?POSTGRES_ADMIN_PASSWORD is required}"
: "${REPLICATION_USER:?REPLICATION_USER is required}"
: "${REPLICATION_PASSWORD:?REPLICATION_PASSWORD is required}"

envsubst \
  '${PATRONI_NAME} ${POSTGRES_ADMIN_USER} ${POSTGRES_ADMIN_PASSWORD} ${REPLICATION_USER} ${REPLICATION_PASSWORD} ${APPLICATION_USER} ${APPLICATION_PASSWORD} ${ANALYST_USER} ${ANALYST_PASSWORD}' \
  < /etc/patroni/patroni.yml.tmpl \
  > /tmp/patroni.yml

chown postgres:postgres /tmp/patroni.yml
chown -R postgres:postgres "$PGDATA"

exec gosu postgres patroni /tmp/patroni.yml
