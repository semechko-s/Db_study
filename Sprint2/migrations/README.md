# Миграции схемы БД сервисного центра

Версионируемые миграции для создания схемы PostgreSQL с нуля.
Используется [golang-migrate](https://github.com/golang-migrate/migrate).

## Файлы

- `001_initial_schema.up.sql` — создание всех 14 таблиц, индексов и ограничений;
- `001_initial_schema.down.sql` — полное удаление схемы.

## Применение

Применить все миграции:

    migrate -path ./migrations \
      -database "postgres://localhost:5432/service_center?sslmode=disable" \
      up

Откатить последнюю:

    migrate -path ./migrations \
      -database "postgres://localhost:5432/service_center?sslmode=disable" \
      down 1

Посмотреть текущую версию:

    migrate -path ./migrations \
      -database "postgres://localhost:5432/service_center?sslmode=disable" \
      version

## Правила

- Старые миграции не редактируются.
- Новые изменения — отдельные пары файлов `002_*.up.sql` / `002_*.down.sql`.

## Соответствие модели

- `request.client_id` отсутствует: клиент определяется через `equipment` (README-5, разделы 4–5).
- `work.request_id` без UNIQUE: связь 1:N (README-5, раздел 6).
- `payment.request_id` UNIQUE: связь 1:1 (README-5, раздел 6).
- `master_assignment`: частичный уникальный индекс обеспечивает не более одного активного мастера на заявку при сохранении истории.