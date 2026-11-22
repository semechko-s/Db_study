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

Эксперимент проверен на MongoDB 9.0.4. Используется отдельный локальный Replica Set из одного узла.

Проверить версию:

```bash
mongod --version
```

В первом терминале запустить сервер:

```bash
mongo_test_dir=$(mktemp -d /tmp/sprint6-mongo.XXXXXX)
mongod --dbpath "$mongo_test_dir" --replSet rsTest --bind_ip 127.0.0.1 --port 37223 --logpath "$mongo_test_dir/server.log"
```

Оставить первый терминал открытым. Во втором инициализировать Replica Set:

```bash
mongosh 'mongodb://127.0.0.1:37223/?directConnection=true' --quiet --eval '
rs.initiate({_id:"rsTest",members:[{_id:0,host:"127.0.0.1:37223"}]});
for(let i=0;i<60;i++){
  if(db.hello().isWritablePrimary){print("PRIMARY готов");quit(0);}
  sleep(500);
}
throw new Error("PRIMARY не появился за 30 секунд");
'
```

После сообщения `PRIMARY готов` перейти в папку проекта и настроить подключение:

```bash
cd /Users/ann/proga/Db_study/Sprint2/mongo_db
export MONGODB_URI='mongodb://127.0.0.1:37223/?replicaSet=rsTest&readConcernLevel=majority&w=majority&readPreference=primary'
```

Запустить проверку и сохранить вывод:

```bash
(
  set -e
  set -o pipefail
  go run . transaction 2>&1 | tee transaction_result.txt
)
```

Ожидаются ошибка валидации `121`, сообщение `AFTER ROLLBACK: reports=0 events=0` и `PASS: partial result is absent`.

После проверки остановить сервер через `Ctrl+C` в первом терминале. Во втором выполнить:

```bash
unset MONGODB_URI
```