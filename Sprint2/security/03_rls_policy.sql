-- RLS (Row-Level Security) для таблицы request.
-- Запускать от имени администратора PostgreSQL (как и 01_roles.sql).
--
-- Естественный сценарий предметной области: аналитик (service_analyst)
-- занимается только статистикой по уже завершённой работе сервисного
-- центра, поэтому не должен видеть заявки, которые ещё в процессе
-- обработки (там может быть незафиксированная цена, незавершённые
-- переговоры с клиентом и т.д.). service_app и service_admin работают
-- с заявками любого статуса, как обычно.

ALTER TABLE request ENABLE ROW LEVEL SECURITY;

-- Аналитик видит только строки, где заявка закрыта.
CREATE POLICY analyst_sees_closed_requests_only
    ON request
    FOR SELECT
    TO service_analyst
    USING (status = 'Закрыта');

-- Приложение и администратор видят и могут изменять все заявки без
-- ограничения по статусу (без этой политики RLS заблокировал бы и их,
-- поскольку RLS действует на все роли, кроме владельца таблицы).
CREATE POLICY admin_app_full_access_to_requests
    ON request
    FOR ALL
    TO service_admin, service_app
    USING (true)
    WITH CHECK (true);

-- Проверка, что RLS включён и видны обе политики:
SELECT relname, relrowsecurity
FROM pg_class
WHERE relname = 'request';

SELECT policyname, roles, cmd
FROM pg_policies
WHERE tablename = 'request'
ORDER BY policyname;
