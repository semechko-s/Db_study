-- ============================================================
-- 002_add_missing_constraints.up.sql
-- Добавление ограничений целостности, реализующих бизнес-правила
-- из README (Спринт 1), которые не попали в 001_initial_schema.
-- Старые миграции не редактируются — это отдельная миграция поверх.
-- ============================================================

-- ------------------------------------------------------------
-- REQUEST
-- ------------------------------------------------------------

-- Правило 6: код причины ОБЯЗАТЕЛЕН в статусе WAITING и ЗАПРЕЩЁН
-- в любом другом статусе. Раньше проверялись только допустимые
-- значения самого waiting_reason, без привязки к status.
ALTER TABLE request
    ADD CONSTRAINT request_waiting_reason_status_chk
    CHECK (
        (status = 'WAITING' AND waiting_reason IS NOT NULL)
        OR (status <> 'WAITING' AND waiting_reason IS NULL)
    );

-- Правило 7: переход в IN_REPAIR (и всё, что после) невозможен
-- без зафиксированного согласия клиента.
ALTER TABLE request
    ADD CONSTRAINT request_repair_requires_approval_chk
    CHECK (status NOT IN ('IN_REPAIR', 'READY', 'CLOSED') OR client_approved = true);

-- Согласие фиксируется только вместе с датой согласия — и наоборот:
-- если approval_at заполнено, client_approved обязано быть true.
ALTER TABLE request
    ADD CONSTRAINT request_approval_at_chk
    CHECK (client_approved = (approval_at IS NOT NULL));

-- Заявку нельзя принять раньше, чем она была создана.
ALTER TABLE request
    ADD CONSTRAINT request_received_after_created_chk
    CHECK (received_at IS NULL OR received_at >= created_at);

-- Правило 13: заявка не может быть закрыта без зафиксированной
-- выдачи устройства клиенту.
ALTER TABLE request
    ADD CONSTRAINT request_closed_requires_issued_chk
    CHECK (status <> 'CLOSED' OR issued_at IS NOT NULL);

-- ------------------------------------------------------------
-- EQUIPMENT — список статусов из жизненного цикла оборудования
-- ------------------------------------------------------------
ALTER TABLE equipment
    ADD CONSTRAINT equipment_status_chk
    CHECK (status IN ('REGISTERED', 'RECEIVED', 'DIAGNOSING', 'IN_REPAIR', 'READY', 'ISSUED'));

-- ------------------------------------------------------------
-- WORK — список статусов из жизненного цикла работы
-- ------------------------------------------------------------
ALTER TABLE work
    ADD CONSTRAINT work_status_chk
    CHECK (status IN ('PLANNED', 'APPROVED', 'IN_PROGRESS', 'DONE', 'CANCELLED'));

ALTER TABLE work
    ADD CONSTRAINT work_ended_after_started_chk
    CHECK (ended_at IS NULL OR started_at IS NULL OR ended_at >= started_at);

-- ------------------------------------------------------------
-- REPAIR — список статусов + PAUSED для правила 11
-- (нехватка запчасти во время ремонта приостанавливает конкретный
-- ремонт, а не всю заявку)
-- ------------------------------------------------------------
ALTER TABLE repair
    ADD CONSTRAINT repair_status_chk
    CHECK (status IN ('PLANNED', 'IN_PROGRESS', 'PAUSED', 'DONE', 'CANCELLED'));

ALTER TABLE repair
    ADD CONSTRAINT repair_ended_after_started_chk
    CHECK (ended_at IS NULL OR started_at IS NULL OR ended_at >= started_at);

-- Правило 10: результат обязателен только для завершённого ремонта
ALTER TABLE repair
    ADD CONSTRAINT repair_result_when_completed_chk
    CHECK (status <> 'DONE' OR result IS NOT NULL);

-- ------------------------------------------------------------
-- PART_RESERVATION — список статусов + защита от двойного резерва
-- ------------------------------------------------------------
ALTER TABLE part_reservation
    ADD CONSTRAINT part_reservation_status_chk
    CHECK (status IN ('ACTIVE', 'USED', 'CANCELLED'));

-- Правило 9: одну и ту же запчасть нельзя зарезервировать дважды
-- активным резервом под один и тот же ремонт.
CREATE UNIQUE INDEX uq_part_reservation_active_per_repair
    ON part_reservation (repair_id, part_id)
    WHERE status = 'ACTIVE';

-- ------------------------------------------------------------
-- USED_PART — одна запчасть списывается по одному ремонту одной записью
-- ------------------------------------------------------------
CREATE UNIQUE INDEX uq_used_part_repair_part
    ON used_part (repair_id, part_id);

-- ------------------------------------------------------------
-- PAYMENT — список статусов + правило про нулевую стоимость (правило 14)
-- ------------------------------------------------------------
ALTER TABLE payment
    ADD CONSTRAINT payment_status_chk
    CHECK (status IN ('PAID', 'NOT_REQUIRED'));

-- Нулевая сумма (гарантийный случай) допустима только со статусом
-- NOT_REQUIRED; положительная сумма — только со статусом PAID.
ALTER TABLE payment
    ADD CONSTRAINT payment_zero_amount_chk
    CHECK ((amount = 0 AND status = 'NOT_REQUIRED') OR (amount > 0 AND status = 'PAID'));

-- ------------------------------------------------------------
-- STATUS_HISTORY
-- ------------------------------------------------------------
ALTER TABLE status_history
    ADD CONSTRAINT status_history_new_status_chk
    CHECK (new_status IN (
        'CREATED', 'ACCEPTED', 'DIAGNOSING', 'WAITING',
        'IN_REPAIR', 'READY', 'CLOSED', 'CANCELLED'
    ));

ALTER TABLE status_history
    ADD CONSTRAINT status_history_different_statuses_chk
    CHECK (old_status IS DISTINCT FROM new_status);

-- ------------------------------------------------------------
-- NOTIFICATION — список статусов доставки
-- ------------------------------------------------------------
ALTER TABLE notification
    ADD CONSTRAINT notification_delivery_status_chk
    CHECK (delivery_status IN ('PENDING', 'SENT', 'FAILED'));

-- ------------------------------------------------------------
-- MASTER_ASSIGNMENT — согласованность дат назначения
-- ------------------------------------------------------------
ALTER TABLE master_assignment
    ADD CONSTRAINT master_assignment_ended_after_assigned_chk
    CHECK (ended_at IS NULL OR ended_at >= assigned_at);

ALTER TABLE master_assignment
    ADD CONSTRAINT master_assignment_active_no_end_chk
    CHECK ((is_active = true AND ended_at IS NULL) OR is_active = false);
