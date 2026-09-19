-- ============================================================
-- 001_initial_schema.up.sql
-- Создание схемы сервисного центра с нуля.
-- Соответствует логической модели PostgreSQL (см. диаграмму)
-- и решениям по нормализации из README-5.
-- ============================================================

-- 1. КЛИЕНТ
CREATE TABLE client (
    id         BIGSERIAL PRIMARY KEY,
    full_name  VARCHAR(255) NOT NULL,
    phone      VARCHAR(30),
    email      VARCHAR(255)
);

-- 2. СОТРУДНИК
CREATE TABLE employee (
    id             BIGSERIAL PRIMARY KEY,
    full_name      VARCHAR(255) NOT NULL,
    specialization VARCHAR(30),
    phone          VARCHAR(30),
    email          VARCHAR(255)
);

-- 3. ОБОРУДОВАНИЕ
CREATE TABLE equipment (
    id                   BIGSERIAL PRIMARY KEY,
    client_id            BIGINT NOT NULL REFERENCES client(id),
    type                 VARCHAR(100) NOT NULL,
    manufacturer         VARCHAR(100) NOT NULL,
    model                VARCHAR(100) NOT NULL,
    serial_number        VARCHAR(100),
    condition_description TEXT,
    status               VARCHAR(30) NOT NULL
);

-- 4. ЗАЯВКА
-- client_id отсутствует намеренно: клиент определяется через equipment.
-- См. README-5, раздел 4-5 (устранение транзитивной зависимости).
CREATE TABLE request (
    id                BIGSERIAL PRIMARY KEY,
    equipment_id      BIGINT NOT NULL REFERENCES equipment(id),
    operator_id       BIGINT REFERENCES employee(id),
    created_at        TIMESTAMP NOT NULL DEFAULT NOW(),
    received_at       TIMESTAMP,
    description       TEXT NOT NULL,
    status            VARCHAR(30) NOT NULL DEFAULT 'CREATED',
    waiting_reason    VARCHAR(40),
    preliminary_cost  NUMERIC(12,2),
    total_cost        NUMERIC(12,2),
    client_approved   BOOLEAN NOT NULL DEFAULT FALSE,
    approval_at       TIMESTAMP,
    issued_at         TIMESTAMP,
    completed_at      TIMESTAMP,
    CONSTRAINT request_status_check CHECK (status IN (
        'CREATED','ACCEPTED','DIAGNOSING','WAITING',
        'IN_REPAIR','READY','CLOSED','CANCELLED'
    )),
    CONSTRAINT request_waiting_reason_check CHECK (
        waiting_reason IS NULL OR waiting_reason IN (
            'CLIENT_APPROVAL','PART_WAITING',
            'ADDITIONAL_DIAGNOSTICS','OTHER'
        )
    ),
    CONSTRAINT request_cost_check CHECK (
        (preliminary_cost IS NULL OR preliminary_cost >= 0)
        AND
        (total_cost IS NULL OR total_cost >= 0)
    )
);

-- 5. РАБОТА
-- work.request_id НЕ UNIQUE: связь request 1:N work (README-5, раздел 6).
CREATE TABLE work (
    id          BIGSERIAL PRIMARY KEY,
    request_id  BIGINT NOT NULL REFERENCES request(id),
    started_at  TIMESTAMP,
    ended_at    TIMESTAMP,
    status      VARCHAR(30) NOT NULL,
    cost        NUMERIC(12,2) NOT NULL DEFAULT 0,
    CONSTRAINT work_cost_check CHECK (cost >= 0)
);

-- 6. ДИАГНОСТИКА
-- request_id UNIQUE: связь request 1:1 diagnosis.
CREATE TABLE diagnosis (
    id                    BIGSERIAL PRIMARY KEY,
    request_id            BIGINT NOT NULL UNIQUE REFERENCES request(id),
    master_id             BIGINT NOT NULL REFERENCES employee(id),
    performed_at          TIMESTAMP NOT NULL DEFAULT NOW(),
    result                TEXT NOT NULL,
    detected_malfunction  TEXT
);

-- 7. РЕМОНТ
-- repair привязан к work (работа 1:N ремонт), а не к request.
CREATE TABLE repair (
    id          BIGSERIAL PRIMARY KEY,
    work_id     BIGINT NOT NULL REFERENCES work(id),
    master_id   BIGINT NOT NULL REFERENCES employee(id),
    description TEXT NOT NULL,
    cost        NUMERIC(12,2) NOT NULL DEFAULT 0,
    result      TEXT,
    started_at  TIMESTAMP,
    ended_at    TIMESTAMP,
    status      VARCHAR(30) NOT NULL,
    CONSTRAINT repair_cost_check CHECK (cost >= 0)
);

-- 8. ЗАПЧАСТЬ
CREATE TABLE part (
    id             BIGSERIAL PRIMARY KEY,
    name           VARCHAR(255) NOT NULL,
    article        VARCHAR(100) UNIQUE,
    price          NUMERIC(12,2) NOT NULL DEFAULT 0,
    stock_quantity INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT part_price_check CHECK (price >= 0),
    CONSTRAINT part_stock_check CHECK (stock_quantity >= 0)
);

-- 9. РЕЗЕРВ ЗАПЧАСТИ
-- Привязан к repair, не к request.
CREATE TABLE part_reservation (
    id           BIGSERIAL PRIMARY KEY,
    repair_id    BIGINT NOT NULL REFERENCES repair(id),
    part_id      BIGINT NOT NULL REFERENCES part(id),
    quantity     INTEGER NOT NULL,
    reserved_at  TIMESTAMP NOT NULL DEFAULT NOW(),
    status       VARCHAR(30) NOT NULL,
    CONSTRAINT part_reservation_quantity_check CHECK (quantity > 0)
);

-- 10. ИСПОЛЬЗОВАННАЯ ЗАПЧАСТЬ
-- Тоже привязана к repair.
CREATE TABLE used_part (
    id             BIGSERIAL PRIMARY KEY,
    repair_id      BIGINT NOT NULL REFERENCES repair(id),
    part_id        BIGINT NOT NULL REFERENCES part(id),
    quantity       INTEGER NOT NULL,
    written_off_at TIMESTAMP NOT NULL DEFAULT NOW(),
    CONSTRAINT used_part_quantity_check CHECK (quantity > 0)
);

-- 11. ОПЛАТА
-- request_id UNIQUE: связь request 1:1 payment (README-5, раздел 6).
CREATE TABLE payment (
    id          BIGSERIAL PRIMARY KEY,
    request_id  BIGINT NOT NULL UNIQUE REFERENCES request(id),
    amount      NUMERIC(12,2) NOT NULL,
    paid_at     TIMESTAMP NOT NULL DEFAULT NOW(),
    method      VARCHAR(30),
    status      VARCHAR(30) NOT NULL,
    CONSTRAINT payment_amount_check CHECK (amount >= 0)
);

-- 12. ИСТОРИЯ СТАТУСОВ
CREATE TABLE status_history (
    id          BIGSERIAL PRIMARY KEY,
    request_id  BIGINT NOT NULL REFERENCES request(id),
    old_status  VARCHAR(30),
    new_status  VARCHAR(30) NOT NULL,
    reason      VARCHAR(255),
    changed_at  TIMESTAMP NOT NULL DEFAULT NOW()
);

-- 13. УВЕДОМЛЕНИЕ
-- Привязано к заявке, не к клиенту.
CREATE TABLE notification (
    id               BIGSERIAL PRIMARY KEY,
    request_id       BIGINT NOT NULL REFERENCES request(id),
    event_type       VARCHAR(50) NOT NULL,
    created_at       TIMESTAMP NOT NULL DEFAULT NOW(),
    delivery_status  VARCHAR(30) NOT NULL
);

-- 14. НАЗНАЧЕНИЕ МАСТЕРА
CREATE TABLE master_assignment (
    id           BIGSERIAL PRIMARY KEY,
    request_id   BIGINT NOT NULL REFERENCES request(id),
    employee_id  BIGINT NOT NULL REFERENCES employee(id),
    assigned_at  TIMESTAMP NOT NULL DEFAULT NOW(),
    ended_at     TIMESTAMP,
    is_active    BOOLEAN NOT NULL DEFAULT TRUE
);

-- Частичный уникальный индекс:
-- по заявке в любой момент активна не более одной записи назначения.
-- История замен сохраняется за счёт is_active = FALSE.
CREATE UNIQUE INDEX master_assignment_one_active_per_request
    ON master_assignment(request_id)
    WHERE is_active = TRUE;

-- Индексы по внешним ключам для типовых запросов
CREATE INDEX idx_equipment_client          ON equipment(client_id);
CREATE INDEX idx_request_equipment         ON request(equipment_id);
CREATE INDEX idx_request_operator          ON request(operator_id);
CREATE INDEX idx_work_request              ON work(request_id);
CREATE INDEX idx_diagnosis_request         ON diagnosis(request_id);
CREATE INDEX idx_diagnosis_master          ON diagnosis(master_id);
CREATE INDEX idx_repair_work               ON repair(work_id);
CREATE INDEX idx_repair_master             ON repair(master_id);
CREATE INDEX idx_part_reservation_repair   ON part_reservation(repair_id);
CREATE INDEX idx_part_reservation_part     ON part_reservation(part_id);
CREATE INDEX idx_used_part_repair          ON used_part(repair_id);
CREATE INDEX idx_used_part_part            ON used_part(part_id);
CREATE INDEX idx_status_history_request    ON status_history(request_id);
CREATE INDEX idx_notification_request      ON notification(request_id);
CREATE INDEX idx_master_assignment_request ON master_assignment(request_id);
CREATE INDEX idx_master_assignment_employee ON master_assignment(employee_id);