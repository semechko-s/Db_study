# Справка
* Для использования скрипта, нужно заходить от имени администратора.
* После задаём пароли для каждого пользователя 
\password service_admin
\password service_app
\password service_analyst
\password service_migrator
* Также можго использовать следующий запрос для проверки результата:
SELECT
    rolname,
    rolcanlogin,
    rolsuper,
    rolcreatedb,
    rolcreaterole,
    rolreplication
FROM pg_roles
WHERE rolname IN (
    'service_admin',
    'service_app',
    'service_analyst',
    'service_migrator'
)
ORDER BY rolname;
* Результат проверки роли service_app есть в result.txt
* Теперь есть отдельная роль для выполнения миграций, но перед его использованием нужно либо полностью снести бд, которая была создана
ранее от другого имени либо переписать права на таблицу и индексы на service_migrator

## Матрица прав (проверено: `security/demo_result.txt`)

| Операция | service_admin | service_app | service_analyst |
|---|:-:|:-:|:-:|
| SELECT | ✅ | ✅ | ✅ |
| INSERT / UPDATE / DELETE | ✅ | ✅ | ❌ |
| TRUNCATE | ✅ | ❌ | ❌ |
| CREATE TABLE в public | ✅ | ❌ | ❌ |
| ALTER / DROP таблиц проекта | только владелец* | ❌ | ❌ |
| Выдача членства в ролях (GRANT роли) | ❌ | ❌ | ❌ |
| CREATE ROLE | ❌ | ❌ | ❌ |
| Чтение pg_authid (хеши паролей) | ❌ | ❌ | ❌ |

\* Владельцем таблиц является роль, под которой применялись миграции. `service_admin` получает `GRANT ALL`, но не становится владельцем.

Проверка: `psql -U <суперпользователь> -d service_center -f security/02_role_permissions_demo.sql`.
Скрипт работает в транзакции с `ROLLBACK`, в базе ничего не остаётся.