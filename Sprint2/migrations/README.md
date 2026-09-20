# Миграции базы данных

В данном каталоге находятся версионные SQL-миграции базы данных
сервисного центра.

## Структура

- `001_create_base_schema.up.sql` — создание основных таблиц базы данных,
  первичных и внешних ключей.
- `001_create_base_schema.down.sql` — откат первой миграции.
- `002_add_constraints_and_indexes.up.sql` — добавление ограничений
  целостности (`CHECK`, `UNIQUE`) и индексов.
- `002_add_constraints_and_indexes.down.sql` — откат второй миграции.

## Запуск миграций

Миграции выполняются последовательно.

## Первая миграция:
psql -d service_center -f 001_create_base_schema.up.sql

## Вторая миграция:
psql -d service_center -f 002_add_constraints_and_indexes.up.sql