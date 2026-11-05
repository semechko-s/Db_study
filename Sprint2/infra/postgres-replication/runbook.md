# Runbook PostgreSQL: запуск, диагностика и восстановление

## 1. Запуск и остановка

Проверить состояние кластеров:

```bash
sudo pg_lsclusters
```

Запустить primary и replica:

```bash
sudo pg_ctlcluster 16 main start
sudo pg_ctlcluster 16 replica start
```

Остановить кластеры:

```bash
sudo pg_ctlcluster 16 replica stop
sudo pg_ctlcluster 16 main stop
```

Перезапускать кластер только при необходимости:

```bash
sudo pg_ctlcluster 16 main restart
sudo pg_ctlcluster 16 replica restart
```

После запуска проверить, что `main` имеет статус `online`, а `replica` — `online,recovery`.

## 2. Проверка работоспособности

Проверить подключение к обоим экземплярам:

```bash
pg_isready -h localhost -p 5432
pg_isready -h localhost -p 5433
```

Проверить роль primary:

```bash
sudo -u postgres psql -p 5432 -c \
"SELECT pg_is_in_recovery();"
```

Ожидаемый результат: `f`.

Проверить роль replica:

```bash
sudo -u postgres psql -p 5433 -c \
"SELECT pg_is_in_recovery();"
```

Ожидаемый результат: `t`.

Проверить подключение реплики на primary:

```bash
sudo -u postgres psql -p 5432 -c "
SELECT application_name, client_addr, state,
       sent_lsn, replay_lsn
FROM pg_stat_replication;"
```

Ожидается состояние `streaming`.

## 3. Диагностика проблем

**Признаки проблемы:**
- кластер не запускается;
- replica не подключается к primary;
- состояние репликации отличается от `streaming`;
- данные на replica отстают от primary.

Проверить статусы:

```bash
sudo pg_lsclusters
```

Посмотреть последние сообщения журналов:

```bash
sudo tail -n 50 /var/log/postgresql/postgresql-16-main.log
sudo tail -n 50 /var/log/postgresql/postgresql-16-replica.log
```

Проверить состояние получателя WAL на replica:

```bash
sudo -u postgres psql -p 5433 -c "
SELECT status, sender_host, sender_port,
       latest_end_lsn, latest_end_time
FROM pg_stat_wal_receiver;"
```

Если кластер не запускается или репликация не работает, сначала изучить сообщения журнала и конфигурацию. Не удалять каталоги данных для устранения ошибки.

## 4. Восстановление после сбоя

1. Проверить состояние обоих кластеров и журналы.
2. Если остановлен primary, выяснить причину и запустить его после устранения проблемы.
3. Если остановлена replica, проверить доступность primary и запустить replica.
4. Убедиться, что реплика подключилась и состояние стало `streaming`.
5. Проверить получение и применение WAL.

**Важно:** автоматического переключения replica в primary нет. При отказе primary реплика может оставаться доступной для чтения, но сама по себе не становится узлом для записи. Не выполнять повторную инициализацию реплики и не удалять данные без отдельного плана восстановления.

## 5. Проверка данных и целостности

Сравнить позиции получения и применения WAL на replica:

```bash
sudo -u postgres psql -p 5433 -c "
SELECT pg_last_wal_receive_lsn() AS received_lsn,
       pg_last_wal_replay_lsn() AS replayed_lsn;"
```

Небольшое отставание возможно при активных изменениях. При отсутствии новых записей позиции обычно сближаются.

Для проверки содержимого базы подключиться к нужной базе на обоих узлах и выполнить одинаковые запросы к контрольным таблицам проекта. Сравнить количество записей и ключевые контрольные данные. Конкретные таблицы и база должны соответствовать фактической схеме проекта.

Если создана резервная копия, проверить её восстановление в отдельную тестовую базу, не перезаписывая рабочие данные. После восстановления сравнить структуру таблиц, контрольные записи и ограничения.
