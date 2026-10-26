# PostgreSQL backup/restore и primary → replica

Этот стенд использует PostgreSQL 17, миграции проекта из `../../migrations`, шаблонную таблицу
`app.replication_probe` для проверяемой записи и три отдельных сервиса:

- `primary` — основной PostgreSQL, принимает записи и отправляет WAL;
- `replica` — standby-сервер, создаваемый через `pg_basebackup`, читает WAL с primary;
- `restore` — отдельная чистая база для проверки резервного копирования и восстановления.

Пароли в `.env` предназначены только для локальной разработки.

## Структура

```text
Sprint2/
├── migrations/
│   ├── 001_create_base_schema.up.sql
│   ├── 002_add_constraints_and_indexes.up.sql
│   ├── 003_prevent_double_part_reservation.up.sql
│   └── 004_optimize_reservation_queries.up.sql
└── infra/
    └── postgres-replication/
        ├── compose.yaml
        ├── .env.example
        ├── .env
        ├── README.md
        ├── EXPERIMENT-LOG-TEMPLATE.md
        ├── primary/init/
        │   ├── 01-initialize-cluster.sh
        │   └── 02-apply-project-migrations.sh
        ├── replica/replica-entrypoint.sh
        ├── sql/
        │   ├── 01-primary-status.sql
        │   ├── 02-create-probe.sql
        │   ├── 03-replica-status.sql
        │   ├── 04-read-probes.sql
        │   ├── 05-integrity-check.sql
        │   └── 06-project-schema-check.sql
        ├── scripts/
        │   ├── backup.sh
        │   └── restore.sh
        └── backups/
```

### Требования и первоначальная настройка

Нужны Docker Desktop и Docker Compose v2.

```bash
cp .env.example .env
set -a
. ./.env
set +a
```

### Первый запуск

```bash
docker compose up -d primary replica
docker compose ps
docker compose logs --tail=100 primary replica
```

Первичная инициализация может занять некоторое время. `01-initialize-cluster.sh` создаёт роли, `app.replication_probe` и правило доступа replication. Затем `02-apply-project-migrations.sh` применяет четыре миграции из `Sprint2/migrations`. Реплика ждёт готовности primary и делает начальную копию через `pg_basebackup`.

Порты на Mac:

- primary: `localhost:55432`;
- replica: `localhost:55433`;
- restore: `localhost:55434`.

## Задание 1. Резервная копия и восстановление в чистый экземпляр PostgreSQL

### 1.1. Подтверждение, что схема проекта создана

```bash
docker compose exec -T primary psql -U "$POSTGRES_ADMIN_USER" -d "$POSTGRES_DB" -f /course/sql/06-project-schema-check.sql
```

Ожидается 14 базовых таблиц в схеме `public`, а также отдельная таблица `app.replication_probe`.

### 1.2. Создание контрольной записи и резервной копии

```bash
docker compose exec -T primary psql -U "$POSTGRES_ADMIN_USER" -d "$POSTGRES_DB" -f /course/sql/02-create-probe.sql
```

```bash
./scripts/backup.sh
```

Скрипт создаёт файл формата `pg_dump -Fc` в `backups/`, проверяет, что архив не пустой, и проверяет возможность прочитать его список объектов. Для собственного пути можно передать аргумент:

```bash
./scripts/backup.sh backups/service-center-manual.dump
```

### 1.3. Восстановление в чистый PostgreSQL

```bash
BACKUP_FILE=$(ls -t backups/*.dump | head -n 1)
echo "$BACKUP_FILE"
./scripts/restore.sh "$BACKUP_FILE"
```

### 1.4. Проверка восстановленных данных

```bash
docker compose exec -T restore psql -U "$POSTGRES_ADMIN_USER" -d "$RESTORE_DB" -f /course/sql/06-project-schema-check.sql
docker compose exec -T restore psql -U "$POSTGRES_ADMIN_USER" -d "$RESTORE_DB" -f /course/sql/04-read-probes.sql
```
На `primary` и `restore` значение `public_base_tables` должно быть равно 14. Это подтверждает, что в обеих базах присутствуют 14 таблиц схемы `public`. Контрольная запись, созданная до backup, должна присутствовать и после восстановления. Это подтверждает и наличие схемы проекта, и перенос данных из архива.

Повторный запуск `./scripts/restore.sh ...` снова создаёт пустую целевую базу перед восстановлением.

## Задание 2. Запуск primary/replica и подтверждение поступлений изменений

### 2.1. Подтверждение ролей

Primary должен возвращать `f` (`false`):

```bash
docker compose exec -T primary psql -U "$POSTGRES_ADMIN_USER" -d "$POSTGRES_DB" -c 'SELECT pg_is_in_recovery();'
```

Replica должен возвращать `t` (`true`):

```bash
docker compose exec -T replica psql -U "$POSTGRES_ADMIN_USER" -d "$POSTGRES_DB" -c 'SELECT pg_is_in_recovery();'
```

### 2.2. Проверка потока репликации на primary

```bash
docker compose exec -T primary psql -U "$POSTGRES_ADMIN_USER" -d "$POSTGRES_DB" -f /course/sql/01-primary-status.sql
```

В `pg_stat_replication` должна быть строка для `service_center_replica`, у которой `state = streaming`.

### 2.3. Запись данных на primary

```bash
docker compose exec -T primary psql -U "$POSTGRES_ADMIN_USER" -d "$POSTGRES_DB" -f /course/sql/02-create-probe.sql
```

Команда вернёт `id`, уникальный `marker` и время записи.

### 2.4. Подтверждение чтения той же записи на replica

```bash
docker compose exec -T replica psql -U "$POSTGRES_ADMIN_USER" -d "$POSTGRES_DB" -f /course/sql/04-read-probes.sql
docker compose exec -T replica psql -U "$POSTGRES_ADMIN_USER" -d "$POSTGRES_DB" -f /course/sql/03-replica-status.sql
```

В таблице на replica должен присутствовать тот же `marker`. В `pg_stat_wal_receiver` ожидается `status = streaming`; LSN получения и применения WAL должны быть заполнены.

Можно проверить конкретный marker вручную:

```bash
docker compose exec -T replica psql -U "$POSTGRES_ADMIN_USER" -d "$POSTGRES_DB" -c "SELECT id, marker, created_at FROM app.replication_probe ORDER BY id DESC LIMIT 5;"
```

### 2.5. Подтверждение, что replica read-only

```bash
docker compose exec -T replica psql -U "$POSTGRES_ADMIN_USER" -d "$POSTGRES_DB" -c "INSERT INTO app.replication_probe(marker) VALUES ('should-fail-on-replica');"
```

Ожидается ошибка о невозможности `INSERT` в read-only transaction. Это ожидаемое поведение standby, а не сбой стенда.

## Ограничения

- Миграции из `primary/init` запускаются только при первом создании пустого `primary_data` volume. Если volume уже был инициализирован, изменение init-скриптов не запустит миграции повторно.
- `replica` создаёт базовую копию при первом старте. Не удаляй volume primary для «починки» реплики. Для полного сброса учебного стенда используй `docker compose down -v` только когда точно готов потерять все данные в трёх volumes.
- Репликация асинхронная: обычно изменения видны почти сразу, но при нагрузке возможна небольшая задержка.
- Этот стенд не выполняет автоматическое повышение replica до primary при отказе primary.
