#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

uri='mongodb://localhost:27117,localhost:27118,localhost:27119/service_center?replicaSet=rs0&readConcernLevel=majority&w=majority&wtimeoutMS=5000&readPreference=primary&serverSelectionTimeoutMS=3000&socketTimeoutMS=5000'
services=(mongo1 mongo2 mongo3)

direct_shell() {
    local service=$1 port=$2
    shift 2
    docker compose exec -T "$service" mongosh --quiet --norc \
        "mongodb://localhost:$port/admin?directConnection=true&serverSelectionTimeoutMS=2000&socketTimeoutMS=5000" "$@"
}

cluster_shell() {
    docker compose exec -T "$runner" mongosh --quiet --norc "$uri" "$@"
}

wait_for() {
    local deadline=$((SECONDS + 90)) result
    until result=$("$@" 2>/dev/null); do
        if (( SECONDS >= deadline )); then
            printf 'Таймаут ожидания: %s\n' "$*" >&2
            "$@"
            return 1
        fi
        sleep 1
    done
    printf '%s\n' "$result"
}

status_js='const s = rs.status();
print(EJSON.stringify({set: s.set, term: s.term, members: s.members.map(m => ({name: m.name, state: m.stateStr, health: m.health}))}));'
ready_js='const members = rs.status().members;
assert.strictEqual(members.length, 3);
assert.strictEqual(members.filter(m => m.health === 1 && m.stateStr === "PRIMARY").length, 1);
assert.strictEqual(members.filter(m => m.health === 1 && m.stateStr === "SECONDARY").length, 2);'
primary_js='const h = db.hello(); assert(h.isWritablePrimary); print(h.primary);'

case "${1:-}" in
    uri)
        printf '%s\n' "$uri"
        ;;
    up)
        docker compose up -d
        for i in "${!services[@]}"; do
            wait_for direct_shell "${services[i]}" "$((27117 + i))" \
                --eval 'assert.strictEqual(db.runCommand({ping: 1}).ok, 1);'
        done
        direct_shell mongo1 27117 --eval '
            try {
                assert.strictEqual(db.adminCommand({replSetGetStatus: 1}).ok, 1);
            } catch (error) {
                if (error.codeName !== "NotYetInitialized") throw error;
                assert.strictEqual(rs.initiate({
                    _id: "rs0",
                    members: [27117, 27118, 27119].map((port, i) => ({
                        _id: i, host: "localhost:" + port
                    }))
                }).ok, 1);
            }
        '
        runner=mongo1
        wait_for cluster_shell --eval "$ready_js"
        cluster_shell --eval "$status_js"
        ;;
    status)
        running=$(docker compose ps --status running --services)
        runner=${running%%$'\n'*}
        if [[ -z "$runner" ]]; then
            printf 'Нет запущенных узлов MongoDB.\n' >&2
            exit 1
        fi
        wait_for cluster_shell --eval "$status_js"
        ;;
    failover)
        runner=mongo1
        wait_for cluster_shell --eval "$ready_js"
        old_primary=$(cluster_shell --eval "$primary_js")
        case "$old_primary" in
            localhost:27117) stopped=mongo1; runner=mongo2 ;;
            localhost:27118) stopped=mongo2 ;;
            localhost:27119) stopped=mongo3 ;;
            *) printf 'Неизвестный primary: %s\n' "$old_primary" >&2; exit 1 ;;
        esac

        probe="failover-$(date -u +%Y%m%dT%H%M%SZ)-$$"
        printf 'До остановки (%s)\n' "$probe"
        cluster_shell --eval "$status_js"
        cluster_shell --eval "
            assert(db.replica_set_probe.insertOne({_id: '$probe', phase: 'before'}).acknowledged);
            print('WRITE before: OK');
        "

        trap 'docker compose start "$stopped" >&2' EXIT
        started=$SECONDS
        docker compose stop "$stopped"
        new_primary=$(wait_for cluster_shell --eval "
            const h = db.hello();
            assert(h.isWritablePrimary);
            assert.notStrictEqual('$old_primary', h.primary);
            print(h.primary);
        ")
        printf 'Primary: %s → %s. От команды остановки до обнаружения прошло %s с.\n' \
            "$old_primary" "$new_primary" "$((SECONDS - started))"
        wait_for cluster_shell --eval "
            assert.strictEqual(rs.status().members.find(m => m.name === '$old_primary').health, 0);
            $status_js
        "
        cluster_shell --eval "
            const probes = db.replica_set_probe;
            assert.strictEqual(probes.findOne({_id: '$probe'}).phase, 'before');
            print('READ before: OK');
            assert(probes.insertOne({_id: '$probe-after', phase: 'after'}).acknowledged);
            assert.strictEqual(probes.findOne({_id: '$probe-after'}).phase, 'after');
            print('WRITE + READ after: OK');
        "

        docker compose start "$stopped"
        trap - EXIT
        wait_for cluster_shell --eval "
            $ready_js
            assert.strictEqual(members.find(m => m.name === '$old_primary').stateStr, 'SECONDARY');
        "
        printf 'После возврата прежнего primary\n'
        cluster_shell --eval "$status_js"
        ;;
    *)
        printf 'Использование: %s {up|uri|status|failover}\n' "$0" >&2
        exit 2
        ;;
esac
