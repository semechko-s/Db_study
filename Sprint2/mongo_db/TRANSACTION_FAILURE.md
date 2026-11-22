# Ошибка между записями транзакции

## Сценарий

После диагностики нужно сохранить подробный протокол в diagnostic_reports и связанное событие diagnosis_recorded в request_events. Обе записи должны фиксироваться вместе.

Базовый сценарий и WithTransaction находятся в существующем transaction.go. В рамках этого эксперимента добавлены явная проверка первой записи внутри транзакции, проверка ошибки валидации с кодом 121 и сообщения о результате отката.

## Внедрение ошибки

1. Для отдельного rollbackID проверяется отсутствие документов в обеих коллекциях.
2. Через InsertOne с SessionContext сохраняется корректный протокол.
3. Через CountDocuments с тем же SessionContext проверяется, что протокол уже виден внутри транзакции.
4. В request_events вставляется событие без обязательного поля author.
5. Серверный валидатор отклоняет вставку. Ошибка возвращается из callback в WithTransaction.
6. После завершения WithTransaction код проверяет, что получена именно ошибка валидации 121.
7. Запросы вне транзакции должны найти 0 протоколов и 0 событий по rollbackID. Любое другое количество завершает программу с ошибкой.

Документы успешного сценария проверяются по другому ID и сохраняются по одной записи в обеих коллекциях. Существующий сценарий временной ошибки также запускается.

## Проверенный результат

Проверка выполнена 22 ноября 2026 года на MongoDB 9.0.4, в отдельном локальном Replica Set из одного узла. URI задаёт primary, majority read concern и majority write concern. Полный вывод сохранён в transaction_result.txt.

```text
SUCCESS: diagnostic report and event committed
BEFORE: reports=0 events=0
INSIDE TRANSACTION: reports=1
EXPECTED ERROR: document validation failed, code=121
AFTER ROLLBACK: reports=0 events=0
PASS: partial result is absent
RETRY: transaction callback executed 2 times; both documents committed
```

INSIDE TRANSACTION доказывает, что первая операция выполнилась. Код 121 подтверждает отказ второй операции из-за валидации. Нулевые счётчики после отката доказывают отсутствие частично сохранённого результата. Временная база service_center_tx_<id> удаляется при обычном завершении сценария.

## Запуск

Из Sprint2/mongo_db при установленном MONGODB_URI выполнить:

```bash
go run . transaction
```

Для выполнения транзакций нужен запущенный Replica Set. Команды развёртывания отдельного локального узла приведены в INSTALL.md.
