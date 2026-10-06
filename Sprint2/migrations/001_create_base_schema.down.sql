-- 001_create_base_schema.down.sql
--
-- Обёрнуто в транзакцию по той же причине, что и up: откат либо проходит
-- целиком, либо не проходит вовсе — частично раскаченного состояния не будет.

BEGIN;

DROP TABLE IF EXISTS notification;
DROP TABLE IF EXISTS status_history;
DROP TABLE IF EXISTS payment;
DROP TABLE IF EXISTS used_part;
DROP TABLE IF EXISTS part_reservation;
DROP TABLE IF EXISTS part;
DROP TABLE IF EXISTS repair;
DROP TABLE IF EXISTS work;
DROP TABLE IF EXISTS diagnosis;
DROP TABLE IF EXISTS master_assignment;
DROP TABLE IF EXISTS request;
DROP TABLE IF EXISTS equipment;
DROP TABLE IF EXISTS employee;
DROP TABLE IF EXISTS client;

DELETE FROM schema_migrations WHERE version = '001';
-- 001 создала реестр — она же его и убирает при полном откате до нуля.
DROP TABLE IF EXISTS schema_migrations;

COMMIT;