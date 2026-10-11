-- 0. Подготовка
DROP TABLE IF EXISTS load_insert;
DROP TABLE IF EXISTS load_copy;

CREATE TABLE load_insert (id INT, name TEXT, value INT);
CREATE TABLE load_copy (id INT, name TEXT, value INT);

-- 1. Замер скорости обычных INSERT
-- Внимание: Вставляем данные пачками, чтобы не повесить базу 500k отдельными запросами
\timing on -- Включаем таймер в psql

INSERT INTO load_insert (id, name, value)
SELECT 
    i, 
    'User_' || i, 
    i * 3
FROM generate_series(1, 500000) AS i;

\timing off

-- 2. Замер скорости COPY
-- Предполагаем, что файл data.csv лежит в корне диска или доступен серверу
-- (Для локального psql укажите полный путь к файлу)
\timing on

COPY load_copy (id, name, value) 
FROM '/полный/путь/к/data.csv' 
WITH (FORMAT csv, HEADER false);

\timing off