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

mkdir -p backups
STAMP=$(date '+%Y%m%d-%H%M%S')
BACKUP_FILE=${1:-"backups/${POSTGRES_DB}-${STAMP}.dump"}

if ! docker compose ps --status running --services | grep -qx primary; then
  echo "Primary is not running. Start it with: docker compose up -d primary replica" >&2
  exit 1
fi

echo "Creating custom-format backup of database '$POSTGRES_DB'..."
docker compose exec -T primary pg_dump \
  --username "$POSTGRES_ADMIN_USER" \
  --dbname "$POSTGRES_DB" \
  --format=custom \
  > "$BACKUP_FILE"

if [ ! -s "$BACKUP_FILE" ]; then
  echo "Backup file is empty: $BACKUP_FILE" >&2
  exit 1
fi

docker compose exec -T primary pg_restore --list < "$BACKUP_FILE" >/dev/null
echo "Backup created and archive listing validated: $BACKUP_FILE"
ls -lh "$BACKUP_FILE"
