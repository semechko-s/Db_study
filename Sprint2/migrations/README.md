# Миграции базы данных service_center

Для версионирования схемы используется **golang-migrate**.

## Структура

migrations/
├── 001_create_base_schema.up.sql
├── 001_create_base_schema.down.sql
├── 002_add_constraints_and_indexes.up.sql
└── 002_add_constraints_and_indexes.down.sql

- `*.up.sql` — применяет миграцию.
- `*.down.sql` — откатывает миграцию.
- Номер в имени файла задаёт порядок миграций.
- Таблицу `schema_migrations` вручную создавать и изменять не нужно: её ведёт `golang-migrate`.

## Установка

Для управления версиями схемы PostgreSQL используется [golang-migrate].

Проверка:

migrate -version

## Основные команды

Из корня проекта:

make createdb
make up
make version
make down
make down-all

### Применить все миграции

make up

`golang-migrate` сам определяет текущую версию и применяет неприменённые миграции по порядку.

### Откатить последнюю миграцию

make down

### Откатить все миграции

make down-all

### Посмотреть текущую версию

make version

### Полностью пересоздать схему

make redo

### Удалить базу

make dropdb

## Рекомендуемая проверка перед сдачей

make dropdb
make createdb
make up
make version
make down
make version
make up
make version

После первого `make up` версия должна быть `2`. После `make down` — `1`. После повторного `make up` — снова `2`.
