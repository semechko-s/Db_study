# Отчёт по оптимизации SQL-запросов

## 1. Цель работы

Исследовать влияние индексов PostgreSQL на производительность SQL-запросов к базе данных `service_center`.

## 2. Выполненные действия

1. Подготовлены тестовые данные.
2. Выполнены два запроса с индексами.
3. Индексы миграции 004 временно удалены, запросы выполнены повторно.
4. Результаты сохранены в файлах `performance_before.txt` и `performance_without_indexes.txt`.
5. Индексы восстановлены и проверены.

### Команды

**Генерация тестовых данных:**

```bash
python scripts/generate_data.py --mode custom --seed 42 --clients 200 --employees 20 --equipment 500 --parts 1000 --requests 500 --works 300 --repairs 300 --reservations 100 --notifications 0
```

Замеры с индексами:

```bash
psql -h 127.0.0.1 -U stas -d service_center -W -f queries/performance_queries.sql > reports/performance_before.txt
```

Удаление индексов миграции 004:

```bash
psql -h 127.0.0.1 -U stas -d service_center -W -f migrations/004_optimize_reservation_queries.down.sql
```

Замеры без индексов:

```bash
psql -h 127.0.0.1 -U stas -d service_center -W -f queries/performance_queries.sql > reports/performance_without_indexes.txt
```

Восстановление индексов:

```bash
psql -h 127.0.0.1 -U stas -d service_center -W -f migrations/004_optimize_reservation_queries.up.sql
```

Проверка индексов:

```bash
psql -h 127.0.0.1 -U stas -d service_center -W \
  -c "SELECT indexname FROM pg_indexes WHERE indexname IN ('idx_part_article', 'idx_part_reservation_active_reserved_at') ORDER BY indexname;"
```

## 3. Результаты

| Запрос | С индексами | Без индексов | Разница |
| --- | ---: | ---: | ---: |
| Подсчёт активных резервов | 0,343 мс | 0,369 мс | +7,58% |
| Отчёт по активным резервам | 7,227 мс | 8,026 мс | +11,05% |

Первый запрос использовал индекс idx_part_article, позволяющий искать запчасти по артикулу без полного сканирования таблицы.
Второй запрос использовал последовательное сканирование и хеш-соединения в обоих случаях. Индекс активных резервов в плане запроса не использовался.

## 4. Вывод

Индекс по артикулу улучшил план выполнения первого запроса. Для второго запроса влияние новых индексов однозначно не подтверждено. Измерения проводились на небольшом объёме данных, поэтому для более точных выводов необходимы дополнительные тесты.
После эксперимента оба индекса миграции 004 восстановлены.
