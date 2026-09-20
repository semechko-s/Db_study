-- ============================================================
-- 002_add_missing_constraints.down.sql
-- Откат добавленных ограничений в обратном порядке.
-- ============================================================

ALTER TABLE master_assignment DROP CONSTRAINT IF EXISTS master_assignment_active_no_end_chk;
ALTER TABLE master_assignment DROP CONSTRAINT IF EXISTS master_assignment_ended_after_assigned_chk;

ALTER TABLE notification DROP CONSTRAINT IF EXISTS notification_delivery_status_chk;

ALTER TABLE status_history DROP CONSTRAINT IF EXISTS status_history_different_statuses_chk;
ALTER TABLE status_history DROP CONSTRAINT IF EXISTS status_history_new_status_chk;

ALTER TABLE payment DROP CONSTRAINT IF EXISTS payment_zero_amount_chk;
ALTER TABLE payment DROP CONSTRAINT IF EXISTS payment_status_chk;

DROP INDEX IF EXISTS uq_used_part_repair_part;

DROP INDEX IF EXISTS uq_part_reservation_active_per_repair;
ALTER TABLE part_reservation DROP CONSTRAINT IF EXISTS part_reservation_status_chk;

ALTER TABLE repair DROP CONSTRAINT IF EXISTS repair_result_when_completed_chk;
ALTER TABLE repair DROP CONSTRAINT IF EXISTS repair_ended_after_started_chk;
ALTER TABLE repair DROP CONSTRAINT IF EXISTS repair_status_chk;

ALTER TABLE work DROP CONSTRAINT IF EXISTS work_ended_after_started_chk;
ALTER TABLE work DROP CONSTRAINT IF EXISTS work_status_chk;

ALTER TABLE equipment DROP CONSTRAINT IF EXISTS equipment_status_chk;

ALTER TABLE request DROP CONSTRAINT IF EXISTS request_closed_requires_issued_chk;
ALTER TABLE request DROP CONSTRAINT IF EXISTS request_received_after_created_chk;
ALTER TABLE request DROP CONSTRAINT IF EXISTS request_approval_at_chk;
ALTER TABLE request DROP CONSTRAINT IF EXISTS request_repair_requires_approval_chk;
ALTER TABLE request DROP CONSTRAINT IF EXISTS request_waiting_reason_status_chk;
