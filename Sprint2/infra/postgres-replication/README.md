# PostgreSQL backup/restore и primary → replica

Этот стенд разворачивает отказоустойчивый кластер PostgreSQL 17 с автоматическим переключением (failover).

В состав входят:
- **etcd1, etcd2, etcd3** — распределенное хранилище конфигурации (DCS) для Patroni.
- **pg1, pg2** — узлы PostgreSQL под управлением Patroni. Один из них — лидер (Leader), второй — синхронная реплика (Sync Standby).
- **haproxy** — балансировщик, который проверяет статус Patroni и направляет запросы только на текущего лидера.
- **restore** — изолированный экземпляр PostgreSQL для проверки резервного копирования и восстановления.

Пароли в `.env` предназначены только для локальной разработки.

## Требования и первоначальная настройка

Нужны Docker Engine (Linux) или Docker Desktop (macOS/Windows) и Docker Compose v2.

```bash
cp .env.example .env
set -a
. ./.env
set +a
```

## Первый запуск

```bash
docker compose up -d
docker compose ps
docker compose logs --tail=100 pg1 pg2
```

Первичная инициализация может занять некоторое время. Patroni дождется etcd, выберет лидера, применит миграции из `Sprint2/migrations` и настроит синхронную репликацию.

Порты на хосте:

- **HAProxy**: `localhost:55432` — единая точка входа для записи и чтения (направляет запросы на текущего лидера).
- **HAProxy Stats**: `localhost:8404` — веб-интерфейс для наблюдения за состоянием бэкендов.
- **restore**: `localhost:55434` — отдельный экземпляр PostgreSQL для восстановления резервной копии.

## Задание 1. Резервная копия и восстановление в чистый экземпляр PostgreSQL

### 1.1. Подтверждение, что схема проекта создана

```bash
docker compose exec -T \
  -e PGPASSWORD="$APPLICATION_PASSWORD" \
  pg2 psql -h haproxy -p 5432 \
  -U "$APPLICATION_USER" -d "$POSTGRES_DB" \
  -f /course/sql/06-project-schema-check.sql
```

Ожидается 14 базовых таблиц в схеме `public`, а также отдельная таблица `app.replication_probe`.

### 1.2. Создание контрольной записи и резервной копии

Создание контрольной записи (через HAProxy):

```bash
docker compose exec -T \
  -e PGPASSWORD="$APPLICATION_PASSWORD" \
  pg2 psql -h haproxy -p 5432 \
  -U "$APPLICATION_USER" -d "$POSTGRES_DB" \
  -f /course/sql/02-create-probe.sql
```

Создание бэкапа:

```bash
./scripts/backup.sh
```

Скрипт `backup.sh` запускает `pg_dump` внутри контейнера `pg2`, но подключается к базе через HAProxy (`haproxy:5432`). Таким образом, резервная копия создается с текущего лидера, независимо от того, какой узел сейчас выполняет эту роль.

После создания скрипт проверяет корректность архива с помощью `pg_restore --list`.

### 1.3. Восстановление в чистый PostgreSQL

```bash
BACKUP_FILE=$(ls -t backups/*.dump | head -n 1)
echo "$BACKUP_FILE"
./scripts/restore.sh "$BACKUP_FILE"
```

Скрипт запускает отдельный экземпляр PostgreSQL `restore`, пересоздает целевую базу `service_center_restored` и восстанавливает в нее данные из резервной копии.

Рабочая база и узлы Patroni при этом не затрагиваются.

### 1.4. Проверка восстановленных данных

```bash
docker compose exec -T restore psql \
  -U "$POSTGRES_ADMIN_USER" -d "$RESTORE_DB" \
  -f /course/sql/06-project-schema-check.sql

docker compose exec -T restore psql \
  -U "$POSTGRES_ADMIN_USER" -d "$RESTORE_DB" \
  -f /course/sql/04-read-probes.sql
```

На рабочей базе и `restore` значение `public_base_tables` должно быть равно 14. Контрольная запись должна присутствовать в восстановленной базе.

## Задание 2. Отказоустойчивость: запись, репликация и автоматический failover

### 2.1. Подтверждение ролей и статуса кластера

```bash
docker compose exec pg1 patronictl -c /etc/patroni/patroni.yml list
```

Ожидается один **Leader** и один **Sync Standby**. Например, `pg2` может быть лидером, а `pg1` — синхронной репликой.

Также можно открыть статистику HAProxy в браузере: [http://localhost:8404/](http://localhost:8404/).

В бэкенде `postgres_primary` сервер-лидер будет в статусе `UP`, а реплика — `DOWN`. Это ожидаемое поведение: HAProxy проверяет endpoint Patroni `/primary`, который возвращает HTTP 200 только на текущем лидере. Реплика продолжает работать и получать WAL, но не принимает запросы через этот backend.

### 2.2. Проверка записи через единую точку входа (HAProxy)

Запись всегда идет через порт `55432`. HAProxy автоматически направит запрос на текущего лидера.

```bash
PGPASSWORD="$APPLICATION_PASSWORD" psql \
  -h 127.0.0.1 -p 55432 \
  -U "$APPLICATION_USER" -d "$POSTGRES_DB" \
  -c "INSERT INTO app.replication_probe(marker)
      VALUES ('before-failover-'||clock_timestamp())
      RETURNING id, marker;"
```

Команда должна вернуть `id` и `marker` (`INSERT 0 1`).

### 2.3. Подтверждение репликации

```bash
docker compose exec -T \
  -e PGPASSWORD="$POSTGRES_ADMIN_PASSWORD" \
  pg1 psql -h 127.0.0.1 \
  -U "$POSTGRES_ADMIN_USER" -d "$POSTGRES_DB" \
  -c "SELECT id, marker FROM app.replication_probe ORDER BY id DESC LIMIT 1;"
```

Запись должна присутствовать на `pg1`, если в данный момент он является синхронной репликой. Так как репликация синхронная, подтвержденная транзакция должна быть передана на реплику до завершения записи.

### 2.4. Имитация падения лидера (Failover)

Перед остановкой узла необходимо проверить, кто сейчас является лидером:

```bash
docker compose exec pg1 patronictl -c /etc/patroni/patroni.yml list
```

Если лидером является `pg2`, выполняем:

```bash
docker compose stop pg2
```

Если лидером является `pg1`, для проверки failover необходимо остановить именно `pg1`:

```bash
docker compose stop pg1
```

**Что должно произойти:**

1. Patroni на оставшемся узле обнаружит потерю связи с лидером через etcd и при соблюдении условий кворума и синхронной репликации повысит его до нового лидера.
2. HAProxy при очередной проверке увидит, что новый лидер теперь отдает `200 OK` на `/primary`, и переключит трафик на него.

Подождать примерно 30–50 секунд. Проверить статус:

```bash
docker compose exec pg1 patronictl -c /etc/patroni/patroni.yml list
```

Если остановлен `pg2`, `pg1` должен стать **Leader**. Если остановлен `pg1`, новым лидером должен стать `pg2`.

### 2.5. Главная проверка: продолжение записи после failover

```bash
PGPASSWORD="$APPLICATION_PASSWORD" psql \
  -h 127.0.0.1 -p 55432 \
  -U "$APPLICATION_USER" -d "$POSTGRES_DB" \
  -c "INSERT INTO app.replication_probe(marker)
      VALUES ('after-failover-'||clock_timestamp())
      RETURNING id, marker;"
```

При успешном переключении HAProxy запрос должен попасть на нового лидера.

**Примечание:** в кластере включён синхронный режим (`synchronous_mode: true`), но строгий режим (`synchronous_mode_strict`) выключен. После failover у нового лидера временно нет синхронной реплики, поэтому Patroni отключает `synchronous_standby_names` и запись продолжает работать в асинхронном режиме. После возврата остановленного узла и его перехода в `Sync Standby` синхронная репликация восстанавливается автоматически.

Если требуется гарантия, что запись не будет подтверждена без синхронной реплики, включите `synchronous_mode_strict: true`. В этом случае после failover запись будет блокироваться до возврата второго узла — это осознанный выбор в пользу сохранности данных вместо доступности.

Проверка, что данные находятся на новом лидере:

```bash
docker compose exec -T \
  -e PGPASSWORD="$POSTGRES_ADMIN_PASSWORD" \
  pg1 psql -h 127.0.0.1 \
  -U "$POSTGRES_ADMIN_USER" -d "$POSTGRES_DB" \
  -c "SELECT id, marker FROM app.replication_probe ORDER BY id;"
```

Если новым лидером стал `pg1`, в таблице должны быть обе записи: `before-failover-*` и `after-failover-*`.

Если новым лидером стал `pg2`, для проверки необходимо выполнить аналогичную команду через `pg2`.

### 2.6. Возврат остановленного узла в кластер

После завершения проверки необходимо запустить остановленный узел.

Например, если ранее был остановлен `pg2`:

```bash
docker compose up -d pg2
```

Проверить состояние кластера:

```bash
docker compose exec pg1 patronictl -c /etc/patroni/patroni.yml list
```

Дождаться, пока запущенный узел присоединится к кластеру и получит роль **Sync Standby**.

Если узел не может автоматически присоединиться к кластеру из-за расхождения таймлайнов WAL, может потребоваться его повторная синхронизация с текущим лидером.

## Ограничения

- **Восстановление старого узла**: После падения лидера при его повторном запуске Patroni может не суметь автоматически присоединить его к кластеру из-за расхождения таймлайнов WAL. Если в `patroni.yml` не настроен `pg_rewind`, узел может потребовать повторной синхронизации с актуальным лидером. Удаление volume и повторное создание узла допустимы только в крайнем случае, после проверки актуальности данных на оставшемся узле. Такая операция приводит к удалению данных соответствующего узла.

- **Синхронная репликация**: В стенде включены `synchronous_mode: true` и `synchronous_mode_strict: false`. В нормальном режиме запись подтверждается синхронной репликой. После failover, пока второй узел не вернулся, Patroni временно работает без синхронной реплики, чтобы сохранить доступность записи; после возврата узла режим `Sync Standby` восстанавливается автоматически. Если включить `synchronous_mode_strict: true`, запись после failover будет блокироваться до появления `Sync Standby` — это снижает доступность, но не допускает подтверждения записи без синхронной реплики.