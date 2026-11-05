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

: "${POSTGRES_DB:?POSTGRES_DB is required}"
: "${POSTGRES_ADMIN_USER:?POSTGRES_ADMIN_USER is required}"
: "${POSTGRES_ADMIN_PASSWORD:?POSTGRES_ADMIN_PASSWORD is required}"

mkdir -p backups

STAMP=$(date '+%Y%m%d-%H%M%S')
BACKUP_FILE=${1:-"backups/${POSTGRES_DB}-${STAMP}.dump"}

if ! docker compose ps --status running --services | grep -qx haproxy; then
  echo "HAProxy is not running. Start it with: docker compose up -d haproxy" >&2
  exit 1
fi

if ! docker compose ps --status running --services | grep -qx pg2; then
  echo "pg2 is not running. Start it with: docker compose up -d pg2" >&2
  exit 1
fi

echo "Creating custom-format backup of database '$POSTGRES_DB' through HAProxy..."

docker compose exec -T \
  -e PGPASSWORD="$POSTGRES_ADMIN_PASSWORD" \
  pg2 pg_dump \
    --host haproxy \
    --port 5432 \
    --username "$POSTGRES_ADMIN_USER" \
    --dbname "$POSTGRES_DB" \
    --format=custom \
    > "$BACKUP_FILE"

if [ ! -s "$BACKUP_FILE" ]; then
  echo "Backup file is empty: $BACKUP_FILE" >&2
  exit 1
fi

echo "Validating backup archive..."

docker compose exec -T pg2 pg_restore --list < "$BACKUP_FILE" >/dev/null

echo "Backup created and archive listing validated: $BACKUP_FILE"
ls -lh "$BACKUP_FILE"