-- ============================================================
-- 001_initial_schema.down.sql
-- Удаление схемы в порядке, обратном созданию.
-- ============================================================

DROP INDEX IF EXISTS master_assignment_one_active_per_request;
DROP INDEX IF EXISTS idx_master_assignment_employee;
DROP INDEX IF EXISTS idx_master_assignment_request;
DROP INDEX IF EXISTS idx_notification_request;
DROP INDEX IF EXISTS idx_status_history_request;
DROP INDEX IF EXISTS idx_used_part_part;
DROP INDEX IF EXISTS idx_used_part_repair;
DROP INDEX IF EXISTS idx_part_reservation_part;
DROP INDEX IF EXISTS idx_part_reservation_repair;
DROP INDEX IF EXISTS idx_repair_master;
DROP INDEX IF EXISTS idx_repair_work;
DROP INDEX IF EXISTS idx_diagnosis_master;
DROP INDEX IF EXISTS idx_diagnosis_request;
DROP INDEX IF EXISTS idx_work_request;
DROP INDEX IF EXISTS idx_request_operator;
DROP INDEX IF EXISTS idx_request_equipment;
DROP INDEX IF EXISTS idx_equipment_client;

DROP TABLE IF EXISTS master_assignment;
DROP TABLE IF EXISTS notification;
DROP TABLE IF EXISTS status_history;
DROP TABLE IF EXISTS payment;
DROP TABLE IF EXISTS used_part;
DROP TABLE IF EXISTS part_reservation;
DROP TABLE IF EXISTS part;
DROP TABLE IF EXISTS repair;
DROP TABLE IF EXISTS diagnosis;
DROP TABLE IF EXISTS work;
DROP TABLE IF EXISTS request;
DROP TABLE IF EXISTS equipment;
DROP TABLE IF EXISTS employee;
DROP TABLE IF EXISTS client;