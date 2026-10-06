-- 001_create_base_schema.up.sql
-- Таблицы, PK и FK. Ограничения CHECK/индексы добавляются миграцией 002.
--
-- Обёрнуто в транзакцию: если любой CREATE TABLE ниже упадёт, откатятся
-- и все уже выполненные в этом запуске CREATE TABLE — частично применённой
-- миграции 001 в базе остаться не может.
--
-- schema_migrations — реестр применённых миграций. Отметка о версии '001'
-- делается последней строкой, внутри той же транзакции: либо схема и
-- отметка коммитятся вместе, либо откатывается всё вместе.

BEGIN;

CREATE TABLE IF NOT EXISTS schema_migrations (
    version    TEXT PRIMARY KEY,
    applied_at TIMESTAMP NOT NULL DEFAULT now()
);

CREATE TABLE client (
 id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 full_name VARCHAR(255) NOT NULL, phone VARCHAR(30), email VARCHAR(255)
);
CREATE TABLE employee (
 id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 full_name VARCHAR(255) NOT NULL, specialization VARCHAR(30), phone VARCHAR(30), email VARCHAR(255)
);
CREATE TABLE equipment (
 id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 client_id BIGINT NOT NULL REFERENCES client(id), type VARCHAR(100) NOT NULL,
 manufacturer VARCHAR(100) NOT NULL, model VARCHAR(100) NOT NULL,
 serial_number VARCHAR(100), condition_description TEXT, status VARCHAR(30) NOT NULL
);
CREATE TABLE request (
 id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 equipment_id BIGINT NOT NULL REFERENCES equipment(id), operator_id BIGINT REFERENCES employee(id),
 created_at TIMESTAMP NOT NULL DEFAULT now(), received_at TIMESTAMP, description TEXT NOT NULL,
 status VARCHAR(30) NOT NULL DEFAULT 'Создана', waiting_reason VARCHAR(40),
 preliminary_cost NUMERIC(12,2), total_cost NUMERIC(12,2),
 client_approved BOOLEAN NOT NULL DEFAULT false, approval_at TIMESTAMP,
 issued_at TIMESTAMP, completed_at TIMESTAMP
);
CREATE TABLE master_assignment (
 id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 request_id BIGINT NOT NULL REFERENCES request(id), employee_id BIGINT NOT NULL REFERENCES employee(id),
 assigned_at TIMESTAMP NOT NULL DEFAULT now(), ended_at TIMESTAMP, is_active BOOLEAN NOT NULL DEFAULT true
);
CREATE TABLE diagnosis (
 id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 request_id BIGINT NOT NULL UNIQUE REFERENCES request(id), master_id BIGINT NOT NULL REFERENCES employee(id),
 performed_at TIMESTAMP NOT NULL DEFAULT now(), result TEXT NOT NULL, detected_malfunction TEXT
);
CREATE TABLE work (
 id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 request_id BIGINT NOT NULL REFERENCES request(id), started_at TIMESTAMP, ended_at TIMESTAMP,
 status VARCHAR(30) NOT NULL DEFAULT 'Запланирована', cost NUMERIC(12,2) NOT NULL
);
CREATE TABLE repair (
 id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 work_id BIGINT NOT NULL REFERENCES work(id), master_id BIGINT NOT NULL REFERENCES employee(id),
 description TEXT NOT NULL, cost NUMERIC(12,2) NOT NULL, result TEXT,
 started_at TIMESTAMP, ended_at TIMESTAMP, status VARCHAR(30) NOT NULL DEFAULT 'Запланирован'
);
CREATE TABLE part (
 id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 name VARCHAR(255) NOT NULL, article VARCHAR(100), price NUMERIC(12,2) NOT NULL,
 stock_quantity INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE part_reservation (
 id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 repair_id BIGINT NOT NULL REFERENCES repair(id), part_id BIGINT NOT NULL REFERENCES part(id),
 quantity INTEGER NOT NULL, reserved_at TIMESTAMP NOT NULL DEFAULT now(), status VARCHAR(30) NOT NULL DEFAULT 'Активен'
);
CREATE TABLE used_part (
 id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 repair_id BIGINT NOT NULL REFERENCES repair(id), part_id BIGINT NOT NULL REFERENCES part(id),
 quantity INTEGER NOT NULL, written_off_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE TABLE payment (
 id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 request_id BIGINT NOT NULL UNIQUE REFERENCES request(id), amount NUMERIC(12,2) NOT NULL,
 paid_at TIMESTAMP, method VARCHAR(30), status VARCHAR(30) NOT NULL
);
CREATE TABLE status_history (
 id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 request_id BIGINT NOT NULL REFERENCES request(id), old_status VARCHAR(30), new_status VARCHAR(30) NOT NULL,
 reason VARCHAR(255), changed_at TIMESTAMP NOT NULL DEFAULT now()
);
CREATE TABLE notification (
 id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
 request_id BIGINT NOT NULL REFERENCES request(id), event_type VARCHAR(50) NOT NULL,
 created_at TIMESTAMP NOT NULL DEFAULT now(), delivery_status VARCHAR(30) NOT NULL DEFAULT 'Ожидает отправки'
);

INSERT INTO schema_migrations (version) VALUES ('001');

COMMIT;