# Краткий отчёт: настройка физической репликации PostgreSQL 16

**ОС:** Ubuntu 24.04  
**Primary:** порт `5432`, кластер `16/main`  
**Replica:** порт `5433`, каталог данных `/var/lib/postgresql/16/replica`

## 1. Создание каталога конфигурации

Команда:
```bash
sudo install -d -o postgres -g postgres -m 755 /etc/postgresql/16/replica/conf.d
```

Результат: команда выполнена без ошибок.

## 2. Проверка параметров конфигурации реплики

Команды:
```bash
sudo grep -nE '^[[:space:]]*(data_directory|port|hba_file|ident_file|external_pid_file|cluster_name|include_dir)[[:space:]]*=' \
  /etc/postgresql/16/replica/postgresql.conf

sudo pg_conftool 16 replica show data_directory
sudo pg_conftool 16 replica show port
```

Результат:
```text
42:data_directory = '/var/lib/postgresql/16/replica'
44:hba_file = '/etc/postgresql/16/replica/pg_hba.conf'
46:ident_file = '/etc/postgresql/16/replica/pg_ident.conf'
50:external_pid_file = '/var/run/postgresql/16-replica.pid'
64:port = 5433
612:cluster_name = '16/replica'
818:include_dir = 'conf.d'
data_directory = /var/lib/postgresql/16/replica
port = 5433
```

## 3. Запуск реплики и проверка списка кластеров

Команды:
```bash
sudo pg_ctlcluster 16 replica start
pg_lsclusters
```

Результат:
```text
Use of uninitialized value $data_directory in concatenation (.) or string at /usr/share/perl5/PgCommon.pm line 286.
Ver Cluster Port      Status Owner     Data directory              Log file
16  main    5432      online postgres  /var/lib/postgresql/16/main /var/log/postgresql/postgresql-16-main.log
16  replica <unknown> down   <unknown> <unknown>                   <unknown>
```

Примечание: `pg_lsclusters` некорректно показывает метаданные `replica` (`<unknown>`), хотя сервер на порту `5433` отвечает.

## 4. Проверка режима реплики и WAL

Команда:
```bash
sudo -u postgres psql -p 5433 -d postgres -c "
SELECT
    pg_is_in_recovery() AS is_replica,
    pg_last_wal_receive_lsn() AS received_lsn,
    pg_last_wal_replay_lsn() AS replayed_lsn,
    pg_last_xact_replay_timestamp() AS last_replay;
"
```

Результат:
```text
 is_replica | received_lsn | replayed_lsn | last_replay
------------+--------------+--------------+-------------
 t          | 0/E000148    | 0/E000148    |
(1 row)
```

Вывод: `pg_is_in_recovery() = t` подтверждает, что экземпляр работает в режиме standby. Полученный и применённый WAL LSN совпадают.

## 5. Проверка подключения на primary

Команда:
```bash
sudo -u postgres psql -p 5432 -d postgres -c "
SELECT
    application_name,
    client_addr,
    state,
    sync_state,
    sent_lsn,
    replay_lsn
FROM pg_stat_replication;
"
```

Результат:
```text
 application_name | client_addr |   state   | sync_state | sent_lsn  | replay_lsn
------------------+-------------+-----------+------------+-----------+------------
 16/replica       | 127.0.0.1   | streaming | async      | 0/E000148 | 0/E000148
(1 row)
```

Вывод: primary видит реплику `16/replica` в состоянии `streaming`; `sent_lsn` и `replay_lsn` совпадают.

## 6. Проверка конфигурационных файлов и журнала

Команды:
```bash
sudo ls -la /etc/postgresql/16/replica/
sudo cat /etc/postgresql/16/replica/start.conf
sudo cat /etc/postgresql/16/replica/pg_ctl.conf
sudo tail -40 /var/log/postgresql/postgresql-16-replica.log
```

Существенные строки вывода:
```text
start.conf:
manual

pg_ctl.conf:
# pg_ctl options
```

В журнале есть старые ошибки о недоступном `conf.d`, а также успешный запуск:
```text
LOG:  listening on IPv4 address "127.0.0.1", port 5433
LOG:  entering standby mode
LOG:  database system is ready to accept read-only connections
LOG:  started streaming WAL from primary at 0/E000000 on timeline 1
```

## Итог

- **Физическая потоковая репликация работает:** primary показывает `state = streaming`.
- **Реплика работает в режиме standby:** `pg_is_in_recovery() = t`.
- На момент проверки `sent_lsn` и `replay_lsn` совпадали: `0/E000148`.
- **Остаётся неисправность отображения `pg_lsclusters`:** кластер `replica` показывается как `<unknown>`. Причина ещё не установлена.
- В `start.conf` указано `manual`; автоматический запуск после перезагрузки пока не подтверждён.
