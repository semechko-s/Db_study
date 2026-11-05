
#!/usr/bin/env bash
set -Eeuo pipefail

PG_VERSION=16
PRIMARY=main
REPLICA=replica
PRIMARY_PORT=5432
REPLICA_PORT=5433
REPL_USER=replicator

PRIMARY_HBA="/etc/postgresql/16/main/pg_hba.conf"
REPLICA_DATA="/var/lib/postgresql/16/replica"
REPLICA_CONF_DIR="/etc/postgresql/16/replica"
REPLICA_CONF="${REPLICA_CONF_DIR}/postgresql.conf"
PGPASS="/var/lib/postgresql/.pgpass-replica"
HBA_RULE="host replication replicator 127.0.0.1/32 scram-sha-256"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

for cmd in psql pg_lsclusters pg_createcluster pg_dropcluster \
           pg_ctlcluster pg_basebackup ss; do
    command -v "$cmd" >/dev/null 2>&1 ||
        die "Missing command: $cmd"
done

sudo -v

[[ "$REPLICA_DATA" == "/var/lib/postgresql/16/replica" ]] ||
    die "Unexpected replica data path."

echo "=== 1. Check primary ==="

sudo pg_ctlcluster "$PG_VERSION" "$PRIMARY" status ||
    die "Primary is not running."

WAL_LEVEL=$(sudo -u postgres psql -X -At \
    -p "$PRIMARY_PORT" -d postgres \
    -c "SHOW wal_level;")

[[ "$WAL_LEVEL" == "replica" ]] ||
    die "Primary wal_level must be replica."

echo "wal_level: $WAL_LEVEL"

echo
echo "=== 2. Check replica port ==="

if sudo ss -ltn | grep -Eq ":${REPLICA_PORT}[[:space:]]"; then
    if ! sudo pg_lsclusters --no-header |
        awk -v p="$REPLICA_PORT" \
            '$2=="replica" && $3==p {found=1} END {exit !found}'; then
        die "Port ${REPLICA_PORT} is occupied by another process."
    fi
fi

echo
echo "=== 3. Configure replication role ==="

read -rsp "Enter password for ${REPL_USER}: " REPL_PASSWORD
echo
[[ -n "$REPL_PASSWORD" ]] || die "Password cannot be empty."

sudo -u postgres psql -X -v ON_ERROR_STOP=1 \
    -v repl_password="$REPL_PASSWORD" \
    -p "$PRIMARY_PORT" -d postgres <<'SQL'
SELECT format(
    CASE WHEN EXISTS (
        SELECT 1 FROM pg_roles WHERE rolname = 'replicator'
    )
    THEN 'ALTER ROLE replicator WITH LOGIN REPLICATION PASSWORD %L'
    ELSE 'CREATE ROLE replicator WITH LOGIN REPLICATION PASSWORD %L'
    END,
    :'repl_password'
) \gexec
SQL

echo
echo "=== 4. Configure primary pg_hba.conf ==="

if ! sudo grep -Fqx "$HBA_RULE" "$PRIMARY_HBA"; then
    echo "$HBA_RULE" | sudo tee -a "$PRIMARY_HBA" >/dev/null
fi

sudo -u postgres psql -X -v ON_ERROR_STOP=1 \
    -p "$PRIMARY_PORT" -d postgres \
    -c "SELECT pg_reload_conf();"

HBA_ERRORS=$(sudo -u postgres psql -X -At \
    -p "$PRIMARY_PORT" -d postgres \
    -c "SELECT count(*) FROM pg_hba_file_rules WHERE error IS NOT NULL;")

[[ "$HBA_ERRORS" == "0" ]] ||
    die "Errors in primary pg_hba.conf."

echo
echo "=== 5. Configure persistent password file ==="

# Escape characters special to .pgpass.
ESCAPED_PASSWORD=${REPL_PASSWORD//\\/\\\\}
ESCAPED_PASSWORD=${ESCAPED_PASSWORD//:/\\:}

TMP_PASS=$(mktemp)
trap 'rm -f "${TMP_PASS:-}"' EXIT

printf '127.0.0.1:%s:replication:%s:%s\n' \
    "$PRIMARY_PORT" "$REPL_USER" "$ESCAPED_PASSWORD" > "$TMP_PASS"

sudo install -o postgres -g postgres -m 600 "$TMP_PASS" "$PGPASS"

rm -f "$TMP_PASS"
TMP_PASS=""

unset ESCAPED_PASSWORD
unset REPL_PASSWORD

echo "Password file configured: $PGPASS"

echo
echo "=== 6. Prepare replica cluster ==="

CLUSTER_EXISTS=false
if sudo pg_lsclusters --no-header |
    awk '$2=="replica" {found=1} END {exit !found}'; then
    CLUSTER_EXISTS=true
fi

if [[ "$CLUSTER_EXISTS" == true || -e "$REPLICA_DATA" ]]; then
    echo "An existing replica cluster or data directory was found."
    echo "Only replica will be rebuilt. Primary main will not be removed."
    read -r -p "Type REBUILD to replace replica data: " ANSWER

    [[ "$ANSWER" == "REBUILD" ]] ||
        die "Cancelled."

    if [[ "$CLUSTER_EXISTS" == true ]]; then
        sudo pg_ctlcluster "$PG_VERSION" "$REPLICA" stop \
            2>/dev/null || true
        sudo pg_dropcluster --stop "$PG_VERSION" "$REPLICA"
    fi

    # Safety check: never remove the primary data directory.
    [[ "$REPLICA_DATA" == "/var/lib/postgresql/16/replica" ]] ||
        die "Refusing to remove unexpected data directory."

    if [[ -e "$REPLICA_DATA" ]]; then
        sudo rm -rf -- "$REPLICA_DATA"
    fi

    if [[ -d "$REPLICA_CONF_DIR" ]]; then
        sudo rm -rf -- "$REPLICA_CONF_DIR"
    fi
fi

if sudo ss -ltn | grep -Eq ":${REPLICA_PORT}[[:space:]]"; then
    die "Port ${REPLICA_PORT} is occupied."
fi

echo
echo "=== 7. Create empty replica data directory ==="

sudo install -d -o postgres -g postgres -m 700 "$REPLICA_DATA"

# pg_basebackup needs an empty destination.
sudo find "$REPLICA_DATA" -mindepth 1 -maxdepth 1 \
    -exec rm -rf -- {} +

sudo chown postgres:postgres "$REPLICA_DATA"
sudo chmod 700 "$REPLICA_DATA"

echo
echo "=== 8. Copy primary data ==="

sudo -u postgres env PGPASSFILE="$PGPASS" pg_basebackup \
    -h 127.0.0.1 \
    -p "$PRIMARY_PORT" \
    -U "$REPL_USER" \
    -D "$REPLICA_DATA" \
    -Fp -Xs -P -R

echo
echo "=== 9. Ensure standby configuration ==="

# Normally -R creates both files. Repair them automatically if needed.
if [[ ! -f "$REPLICA_DATA/standby.signal" ]]; then
    echo "Creating missing standby.signal"
    sudo -u postgres touch "$REPLICA_DATA/standby.signal"
fi

if [[ ! -f "$REPLICA_DATA/postgresql.auto.conf" ]]; then
    echo "Creating missing postgresql.auto.conf"
    sudo -u postgres touch "$REPLICA_DATA/postgresql.auto.conf"
fi

# Use a persistent password file instead of embedding the password
# in postgresql.auto.conf. Replace any primary_conninfo generated by -R.
sudo sed -i \
    '/^[[:space:]]*primary_conninfo[[:space:]]*=/d' \
    "$REPLICA_DATA/postgresql.auto.conf"

sudo tee -a "$REPLICA_DATA/postgresql.auto.conf" >/dev/null <<EOF

# Managed by setup-native-replica_7.sh
primary_conninfo = 'host=127.0.0.1 port=${PRIMARY_PORT} user=${REPL_USER} application_name=16/replica passfile=${PGPASS}'
EOF

sudo chown postgres:postgres \
    "$REPLICA_DATA/standby.signal" \
    "$REPLICA_DATA/postgresql.auto.conf"

sudo chmod 600 "$REPLICA_DATA/postgresql.auto.conf"

echo
echo "=== 10. Register existing physical backup as a cluster ==="

# Important: register the already-copied data directory.
# Do NOT run initdb over the physical backup.
sudo pg_createcluster "$PG_VERSION" "$REPLICA" \
    --datadir="$REPLICA_DATA" \
    --port="$REPLICA_PORT" \
    --start-conf=manual

echo
echo "=== 11. Configure replica server ==="

{
    echo
    echo "# Managed by setup-native-replica_7.sh"
    echo "listen_addresses = '127.0.0.1'"
    echo "port = ${REPLICA_PORT}"
    echo "hot_standby = on"
} | sudo tee -a "$REPLICA_CONF" >/dev/null

sudo chown postgres:postgres "$REPLICA_DATA"
sudo chmod 700 "$REPLICA_DATA"

echo
echo "=== 12. Start replica ==="

if ! sudo pg_ctlcluster "$PG_VERSION" "$REPLICA" start; then
    sudo tail -n 80 \
        "/var/log/postgresql/postgresql-16-replica.log" || true
    die "Replica failed to start."
fi

echo
echo "=== 13. Verify recovery mode ==="

RECOVERY=$(sudo -u postgres psql -X -At \
    -p "$REPLICA_PORT" -d postgres \
    -c "SELECT pg_is_in_recovery();")

[[ "$RECOVERY" == "t" ]] ||
    die "Replica is not in recovery mode."

echo "Replica recovery mode: $RECOVERY"

echo
echo "=== 14. Wait for streaming ==="

STREAMING=false

for _ in $(seq 1 30); do
    STATE=$(sudo -u postgres psql -X -At \
        -p "$PRIMARY_PORT" -d postgres \
        -c "SELECT coalesce(
            (SELECT state
             FROM pg_stat_replication
             WHERE application_name = '16/replica'
             LIMIT 1), 'none');")

    if [[ "$STATE" == "streaming" ]]; then
        STREAMING=true
        break
    fi

    sleep 1
done

pg_lsclusters

sudo -u postgres psql -X -p "$PRIMARY_PORT" -d postgres \
    -c "SELECT application_name, client_addr, state, sync_state
        FROM pg_stat_replication;"

[[ "$STREAMING" == true ]] ||
    die "Replica started, but streaming was not confirmed."

echo
echo "SUCCESS: native streaming replication is running."
echo "Primary: localhost:${PRIMARY_PORT}"
echo "Replica: localhost:${REPLICA_PORT}"
