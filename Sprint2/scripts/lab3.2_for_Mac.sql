-- 0. Подготовка
DROP TABLE IF EXISTS load_insert;
DROP TABLE IF EXISTS load_copy;

CREATE TABLE load_insert (
    id INT,
    name TEXT,
    value INT
);

CREATE TABLE load_copy (
    id INT,
    name TEXT,
    value INT
);

-- 1. Замер INSERT ... SELECT
\timing on

INSERT INTO load_insert (id, name, value)
SELECT i, 'User_' || i, i * 3
FROM generate_series(1, 500000) AS i;

\timing off

-- 2. Создание CSV-файла на компьютере
\copy (SELECT i, 'User_' || i, i * 3 FROM generate_series(1, 500000) AS i) TO '/tmp/data.csv' WITH (FORMAT csv, HEADER false)

-- 3. Замер COPY
\timing on

\copy load_copy (id, name, value) FROM '/tmp/data.csv' WITH (FORMAT csv, HEADER false)

\timing off

-- 4. Проверка количества строк
SELECT 'load_insert' AS table_name, COUNT(*) AS row_count
FROM load_insert
UNION ALL
SELECT 'load_copy', COUNT(*)
FROM load_copy;

-- 5. Проверка совпадения данных
SELECT COUNT(*) AS different_rows
FROM load_insert i
FULL JOIN load_copy c ON i.id = c.id
WHERE i.id IS DISTINCT FROM c.id
   OR i.name IS DISTINCT FROM c.name
   OR i.value IS DISTINCT FROM c.value;