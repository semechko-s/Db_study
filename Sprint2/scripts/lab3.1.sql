-- 0. Подготовка: Удаляем старые таблицы, если есть
DROP TABLE IF EXISTS test_no_index;
DROP TABLE IF EXISTS test_with_index;

-- 1. Создаем таблицу БЕЗ индекса
CREATE TABLE test_no_index (
    id SERIAL PRIMARY KEY,
    user_id INT,
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- 2. Замеряем время вставки 1 000 000 строк без индекса
-- (Используем generate_series для быстрой генерации данных)
EXPLAIN ANALYZE 
INSERT INTO test_no_index (user_id, description)
SELECT 
    (random() * 10000)::int, 
    'Test description for user ' || i 
FROM generate_series(1, 1000000) AS i;

-- Запишите время выполнения (Execution Time), которое выдаст EXPLAIN ANALYZE


-- 3. Создаем таблицу С индексом (структура идентична)
CREATE TABLE test_with_index (
    id SERIAL PRIMARY KEY,
    user_id INT,
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW()
);

-- 4. Создаем индекс на поле user_id
CREATE INDEX idx_test_user_id ON test_with_index(user_id);

-- 5. Замеряем время вставки 1 000 000 строк С индексом
EXPLAIN ANALYZE 
INSERT INTO test_with_index (user_id, description)
SELECT 
    (random() * 10000)::int, 
    'Test description for user ' || i 
FROM generate_series(1, 1000000) AS i;

-- Сравните время выполнения с пунктом 2. Оно будет больше.


-- 6. Сравниваем размеры таблиц (включая индексы)
SELECT 
    'Без индекса' as type, 
    pg_size_pretty(pg_total_relation_size('test_no_index')) as total_size
UNION ALL
SELECT 
    'С индексом', 
    pg_size_pretty(pg_total_relation_size('test_with_index'));