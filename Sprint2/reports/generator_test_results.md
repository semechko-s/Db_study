# Результаты тестирования генератора данных

## 1. Проверка запуска

Команда:
python3 scripts/generate_data.py --help

Результат: справка генератора сохранена в generator_help.txt.

## 2. Проверка синтаксиса

Команда:
python3 -m py_compile scripts/generate_data.py

Результат: успешно, ошибок синтаксиса нет.

## 3. Режим development

Команда:
python3 scripts/generate_data.py --mode development --seed 44 --batch-size 1000

Результат: транзакция успешно зафиксирована.

Добавлено:
- client: 100
- employee: 20
- equipment: 300
- part: 50
- request: 300
- master_assignment: 100
- diagnosis: 150
- work: 250
- repair: 200
- part_reservation: 150
- used_part: 100
- payment: 200
- status_history: 1000
- notification: 100000

## 4. Режим load

Команда:
python3 scripts/generate_data.py --mode load --seed 45 --batch-size 1000

Результат: транзакция успешно зафиксирована.

Добавлено:
- client: 100
- employee: 20
- equipment: 300
- part: 100
- request: 1000
- master_assignment: 100
- diagnosis: 150
- work: 500
- repair: 400
- part_reservation: 200
- used_part: 150
- payment: 500
- status_history: 3000
- notification: 3000000

## 5. Итоговое количество записей

| Таблица | Записей |
|---|---:|
| client | 214 |
| employee | 47 |
| equipment | 619 |
| part | 164 |
| request | 1307 |
| master_assignment | 203 |
| diagnosis | 303 |
| work | 755 |
| repair | 603 |
| part_reservation | 353 |
| used_part | 253 |
| payment | 703 |
| status_history | 4008 |
| notification | 3100013 |

## 6. Проверка масштабов генерации

### Режим development

Для проверки режима разработки создана отдельная чистая база данных `service_center_generator_dev`. После применения миграций выполнена команда:

`python3 scripts/generate_data.py --mode development --seed 44 --batch-size 1000`

Генерация завершилась успешно, транзакция зафиксирована. В таблицу `notification` добавлено 100 000 записей. Контрольный запрос `SELECT COUNT(*) FROM notification` подтвердил наличие ровно 100 000 строк.

**Результат:** требование от 50 000 до 100 000 строк в крупнейшей таблице выполнено.

### Режим load

Для проверки нагрузочного режима создана отдельная чистая база данных `service_center_generator_load`. После применения миграций выполнена команда:

`python3 scripts/generate_data.py --mode load --seed 45 --batch-size 1000`

Генерация завершилась успешно, транзакция зафиксирована. В таблицу `notification` добавлено 3 000 000 записей. Контрольный запрос `SELECT COUNT(*) FROM notification` подтвердил наличие ровно 3 000 000 строк.

**Результат:** требование не менее 3 000 000 строк в крупнейшей таблице выполнено.

### Итог

Оба режима генерации протестированы на отдельных чистых базах данных. Фактические размеры крупнейшей таблицы подтверждены запросами к PostgreSQL. Оба требования к масштабам генерации выполнены.

## 7. Проверки целостности

Шесть проверок логической целостности завершились успешно.
Количество ошибок во всех проверках: 0.

Проверка ограничений PostgreSQL:
- Всего ограничений: 66
- Непроверенных ограничений: 0

## 8. Вывод

Генератор успешно отработал в режимах development и load.
В таблице notification создано 3100013 записей.
Проверенные условия логической целостности соблюдены.
Все 66 ограничений схемы public валидированы.
