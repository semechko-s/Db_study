# Справка
* Для использования скрипта, нужно заходить от имени администратора.
* После задаём пароли для каждого пользователя 
\password service_admin
\password service_app
\password service_analyst
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
    'service_analyst'
)
ORDER BY rolname;
* Результат проверки роли service_app есть в result.txt
* (Следует уточнить, от какого имени будут выполнятся миграции, дабы можно было настроить будущие привилегии и избежать проблем при следующих миграциях)