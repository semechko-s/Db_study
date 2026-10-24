#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$SCRIPT_DIR"
if [ ! -f .env ]; then
  echo "Missing .env. Run: cp .env.example .env" >&2
  exit 1
fi
set -a
. ./.env
set +a

BACKUP_FILE=${1:-}
if [ -z "$BACKUP_FILE" ]; then
  echo "Usage: ./scripts/restore.sh path/to/backup.dump" >&2
  exit 2
fi
case "$BACKUP_FILE" in
  /*) ;;
  *) BACKUP_FILE="$SCRIPT_DIR/$BACKUP_FILE" ;;
esac
if [ ! -s "$BACKUP_FILE" ]; then
  echo "Backup file not found or empty: $BACKUP_FILE" >&2
  exit 1
fi

echo "Starting clean restore instance '$RESTORE_DB'..."
docker compose --profile restore up -d restore
attempt=0
until docker compose exec -T restore pg_isready \
  --username "$POSTGRES_ADMIN_USER" --dbname "$RESTORE_DB" >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 30 ]; then
    echo "Restore PostgreSQL did not become ready." >&2
    docker compose logs --tail=100 restore >&2
    exit 1
  fi
  sleep 2
done

echo "Recreating an empty database '$RESTORE_DB' on the isolated restore instance..."
# The restore service has its own volume. Recreate only its target database,
# never the primary or replica databases.
docker compose exec -T restore psql \
  --username "$POSTGRES_ADMIN_USER" --dbname postgres \
  --set=ON_ERROR_STOP=1 <<SQL
DROP DATABASE IF EXISTS "$RESTORE_DB";
CREATE DATABASE "$RESTORE_DB";
SQL

echo "Restoring $BACKUP_FILE into '$RESTORE_DB'..."
docker compose exec -T restore pg_restore \
  --exit-on-error \
  --single-transaction \
  --no-owner --no-privileges \
  --username "$POSTGRES_ADMIN_USER" \
  --dbname "$RESTORE_DB" < "$BACKUP_FILE"

echo "Restore completed. Table inventory:"
docker compose exec -T restore psql \
  --username "$POSTGRES_ADMIN_USER" --dbname "$RESTORE_DB" \
  --no-align --tuples-only \
  --command "SELECT table_schema || '.' || table_name FROM information_schema.tables WHERE table_type='BASE TABLE' AND table_schema IN ('public','app') ORDER BY table_schema, table_name;"
