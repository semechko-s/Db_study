#!/bin/sh
set -eu

: "${POSTGRES_DB:?POSTGRES_DB is required}"
: "${POSTGRES_USER:?POSTGRES_USER is required}"

MIGRATIONS_DIR=/course/migrations
for migration in \
  "$MIGRATIONS_DIR/001_create_base_schema.up.sql" \
  "$MIGRATIONS_DIR/002_add_constraints_and_indexes.up.sql" \
  "$MIGRATIONS_DIR/003_prevent_double_part_reservation.up.sql" \
  "$MIGRATIONS_DIR/004_optimize_reservation_queries.up.sql"
do
  if [ ! -f "$migration" ]; then
    echo "Migration not found: $migration" >&2
    exit 1
  fi
  echo "Applying project migration: $(basename "$migration")"
  psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    --set=ON_ERROR_STOP=1 --file "$migration"
done

echo "Project schema is ready."
