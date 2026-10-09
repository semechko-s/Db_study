#!/usr/bin/env python3
"""Воспроизводимый генератор тестовых данных для Sprint2.

Повторные запуски используют MAX(id) для сдвига тестовых телефонов, email-индексов,
серийных номеров оборудования и артикулов, снижая риск совпадений.

Генератор наполняет основные таблицы и постепенно расширяется на связанные таблицы.
Схема и имена столбцов сверены с миграциями Sprint2/migrations/001 и 002.

Установка драйвера:
    python -m pip install "psycopg[binary]>=3.1,<4"

Пример запуска из каталога Sprint2:
    python scripts/generate_data.py --seed 42
    python scripts/generate_data.py --seed 42 --clients 1000 --equipment 5000

Настройки подключения читаются из PGHOST, PGPORT, PGDATABASE, PGUSER,
PGPASSWORD. По умолчанию используются localhost:5432, база postgres,
пользователь postgres.

Важно: скрипт добавляет данные и не очищает таблицы. Одинаковый seed делает
генерируемые значения повторяемыми, но ID зависят от состояния БД и sequence.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timedelta
import os
import random
import sys
from typing import Sequence

try:
    import psycopg
except ImportError:  # Сообщим об установке понятным сообщением в main().
    psycopg = None  # type: ignore[assignment]


FIRST_NAMES = [
    "Александр", "Алексей", "Андрей", "Анна", "Арина", "Виктор", "Дарья",
    "Дмитрий", "Екатерина", "Елена", "Иван", "Ирина", "Кирилл", "Мария",
    "Максим", "Михаил", "Наталья", "Никита", "Ольга", "Павел", "Полина",
    "Роман", "Светлана", "Сергей", "София", "Татьяна", "Юлия",
]
LAST_NAMES = [
    "Алексеев", "Андреев", "Белов", "Васильев", "Волков", "Григорьев",
    "Данилов", "Егоров", "Жуков", "Зайцев", "Иванов", "Козлов", "Кузнецов",
    "Макаров", "Морозов", "Никитин", "Орлов", "Павлов", "Попов", "Романов",
    "Семенов", "Смирнов", "Соколов", "Федоров", "Фролов", "Яковлев",
]
PATRONYMICS = [
    "Александрович", "Алексеевич", "Андреевич", "Викторович",
    "Дмитриевич", "Иванович", "Михайлович", "Сергеевич",
    "Александровна", "Алексеевна", "Андреевна", "Викторовна",
    "Дмитриевна", "Ивановна", "Михайловна", "Сергеевна",
]

GENERATION_REFERENCE_TIME = datetime(2026, 10, 9, 12, 0, 0)

EQUIPMENT_TYPES = [
    "Ноутбук", "Смартфон", "Планшет", "Стационарный компьютер",
    "Монитор", "Принтер", "Игровая консоль", "Роутер",
]
MANUFACTURER_MODELS = {
    "Apple": ["MacBook Air", "MacBook Pro", "iPhone", "iPad"],
    "ASUS": ["VivoBook", "ZenBook", "ROG", "TUF Gaming"],
    "Acer": ["Aspire", "Swift", "Nitro"],
    "Dell": ["Inspiron", "XPS", "Latitude"],
    "HP": ["Pavilion", "Envy", "LaserJet"],
    "Lenovo": ["ThinkPad", "IdeaPad", "Legion"],
    "Samsung": ["Galaxy", "Galaxy Tab", "Odyssey"],
    "Xiaomi": ["Redmi", "POCO", "Mi Pad"],
    "Canon": ["PIXMA", "imageCLASS"],
    "Epson": ["EcoTank", "Expression"],
}
REQUEST_STATUSES = [
    "Создана", "Принята", "На диагностике", "Ожидание",
    "В ремонте", "Готова", "Закрыта", "Отменена",
]
WAITING_REASONS = ["CLIENT_APPROVAL", "PART_WAITING", "ADDITIONAL_DIAGNOSTICS", "OTHER"]
REQUEST_DESCRIPTIONS = [
    "Не включается устройство", "Проблема с зарядкой", "Повреждён экран",
    "Устройство перегревается", "Не работает клавиатура", "Посторонний шум",
    "Требуется диагностика", "Нестабильная работа устройства",
]

WORK_STATUSES = ["Запланирована", "Согласована", "Выполняется", "Завершена", "Отменена"]

EQUIPMENT_STATUSES = [
    "Зарегистрировано", "Принято в сервис", "На диагностике",
    "На ремонте", "Готово к выдаче", "Выдано",
]
PART_NAMES = [
    "Аккумулятор", "Блок питания", "Вентилятор охлаждения",
    "Дисплейный модуль", "Клавиатура", "Матрица экрана",
    "Материнская плата", "Оперативная память", "Разъём питания",
    "SSD-накопитель", "Термопаста", "Шлейф дисплея",
    "Сетевой адаптер", "Кабель USB", "Корпусная деталь",
]


def weighted_choice(
    rng: random.Random,
    values: Sequence[str],
    weights: Sequence[int],
) -> str:
    """Выбирает значение с учётом заданных весов."""
    if len(values) != len(weights):
        raise ValueError("Количество значений и весов должно совпадать.")
    if not values or any(weight < 0 for weight in weights):
        raise ValueError("Значения должны быть непустыми, веса — неотрицательными.")
    if sum(weights) == 0:
        raise ValueError("Сумма весов должна быть больше нуля.")
    return rng.choices(values, weights=weights, k=1)[0]


def make_full_name(rng: random.Random) -> str:
    """Составляет синтетическое ФИО; выборы зависят от переданного RNG."""
    return f"{rng.choice(LAST_NAMES)} {rng.choice(FIRST_NAMES)} {rng.choice(PATRONYMICS)}"


def make_email(rng: random.Random, index: int, domain: str) -> str:
    """Формирует адрес на зарезервированном тестовом домене example.test."""
    token = rng.getrandbits(40)
    return f"user{index}_{token:010x}@{domain}"


def make_phone(index: int) -> str:
    """Создаёт синтетический тестовый номер; диапазон повторяется после 1 млн значений."""
    return f"+7999{index % 1_000_000:06d}"


def next_id_offset(cursor: "psycopg.Cursor", table: str) -> int:
    """Возвращает MAX(id) + 1, чтобы индексы тестовых значений не начинались заново."""
    # table вызывается только с фиксированными именами из этого скрипта.
    cursor.execute(f'SELECT COALESCE(MAX(id), 0) + 1 FROM "{table}"')
    return int(cursor.fetchone()[0])


def insert_many(
    cursor: "psycopg.Cursor",
    table: str,
    columns: Sequence[str],
    rows: Sequence[Sequence[object]],
    batch_size: int,
) -> list[int]:
    """Вставляет строки пакетами и возвращает сгенерированные ID."""
    inserted_ids: list[int] = []
    if not rows:
        return inserted_ids

    columns_sql = ", ".join(f'"{column}"' for column in columns)
    placeholders_per_row = "(" + ", ".join(["%s"] * len(columns)) + ")"

    for offset in range(0, len(rows), batch_size):
        batch = rows[offset : offset + batch_size]
        values_sql = ", ".join([placeholders_per_row] * len(batch))
        sql = f'INSERT INTO "{table}" ({columns_sql}) VALUES {values_sql} RETURNING id'
        params = tuple(value for row in batch for value in row)
        cursor.execute(sql, params)
        inserted_ids.extend(row[0] for row in cursor.fetchall())

    return inserted_ids


def generate_clients(
    rng: random.Random, count: int, start_index: int = 1
) -> list[tuple[object, ...]]:
    rows = []
    for index in range(start_index, start_index + count):
        # client_contact_present требует телефон или email хотя бы для одного поля.
        phone = make_phone(index) if rng.random() < 0.65 else None
        email = make_email(rng, index, "example.test")
        rows.append((make_full_name(rng), phone, email))
    return rows


def generate_employees(
    rng: random.Random, count: int, start_index: int = 1
) -> list[tuple[object, ...]]:
    rows = []
    for index in range(start_index, start_index + count):
        # Гарантируем мастера в каждой новой группе сотрудников, если она не пуста.
        # Это позволяет профилям development/load создавать назначения и ремонты.
        position = index - start_index
        specialization = "Мастер" if position == 0 or position % 4 == 0 else ("Оператор" if position % 4 == 1 else None)
        rows.append(
            (
                make_full_name(rng),
                specialization,
                make_phone(500_000 + index),
                make_email(rng, 500_000 + index, "service.example.test"),
            )
        )
    return rows


def generate_equipment(
    rng: random.Random, client_ids: Sequence[int], count: int, start_index: int = 1
) -> list[tuple[object, ...]]:
    if count > 0 and not client_ids:
        raise ValueError("Нельзя создать оборудование без клиентов: client_id обязателен.")

    rows = []
    manufacturers = list(MANUFACTURER_MODELS)
    for index in range(start_index, start_index + count):
        manufacturer = rng.choice(manufacturers)
        model = rng.choice(MANUFACTURER_MODELS[manufacturer])
        serial_number = f"GEN-{manufacturer[:3].upper()}-{index:010d}"
        condition = rng.choice(
            [
                "Внешних повреждений не обнаружено",
                "Есть следы эксплуатации",
                "Небольшие царапины на корпусе",
                "Состояние не оценивалось",
            ]
        )
        rows.append(
            (
                rng.choice(client_ids),
                weighted_choice(rng, EQUIPMENT_TYPES, [30, 25, 12, 10, 7, 6, 5, 5]),
                manufacturer,
                model,
                serial_number,
                condition,
                rng.choice(EQUIPMENT_STATUSES),
            )
        )
    return rows


def generate_parts(
    rng: random.Random, count: int, start_index: int = 1
) -> list[tuple[object, ...]]:
    rows = []
    for index in range(start_index, start_index + count):
        name = rng.choice(PART_NAMES)
        article = f"GEN-PART-{index:08d}"
        price = round(rng.uniform(100, 45_000), 2)
        stock_quantity = rng.randint(0, 250)
        rows.append((f"{name} №{index}", article, price, stock_quantity))
    return rows



def fetch_ids(cursor: "psycopg.Cursor", table: str) -> list[int]:
    """Получает существующие ID из одной из фиксированных таблиц генератора."""
    cursor.execute(f'SELECT id FROM "{table}" ORDER BY id')
    return [int(row[0]) for row in cursor.fetchall()]


def generate_requests(
    rng: random.Random, equipment_ids: Sequence[int], operator_ids: Sequence[int], count: int
) -> list[tuple[object, ...]]:
    """Создаёт заявки с согласованными статусами, датами и полями согласования."""
    if count > 0 and not equipment_ids:
        raise ValueError("Нельзя создать заявки без оборудования: equipment_id обязателен.")

    if count > 0 and not operator_ids:
        raise ValueError("Нельзя создать заявки: нет сотрудников со специализацией 'Оператор'.")

    rows = []
    now = GENERATION_REFERENCE_TIME
    for _ in range(count):
        created_at = now - timedelta(days=rng.randint(0, 730), hours=rng.randint(0, 23))
        received_at = min(now, created_at + timedelta(hours=rng.randint(0, 48))) if rng.random() < 0.85 else None
        status = weighted_choice(rng, REQUEST_STATUSES, [8, 12, 15, 15, 20, 12, 14, 4])
        approved = status in ("В ремонте", "Готова", "Закрыта") or (
            status == "Ожидание" and rng.random() < 0.4
        )
        approval_at = created_at + timedelta(hours=rng.randint(1, 72)) if approved else None
        # Не допускаем approval_at в будущем относительно текущего времени.
        if approval_at is not None and approval_at > now:
            approval_at = now
        waiting_reason = rng.choice(WAITING_REASONS) if status == "Ожидание" else None
        issued_at = None
        completed_at = None
        if status == "Закрыта":
            issued_at = max(created_at, min(now, created_at + timedelta(days=rng.randint(1, 20))))
            completed_at = issued_at
        elif status == "Готова":
            completed_at = min(now, created_at + timedelta(days=rng.randint(1, 20)))
        preliminary_cost = round(rng.uniform(300, 15000), 2) if rng.random() < 0.8 else None
        total_cost = round(rng.uniform(300, 60000), 2) if status in ("Готова", "Закрыта") else None
        rows.append((
            rng.choice(equipment_ids),
            rng.choice(operator_ids) if rng.random() < 0.8 else None,
            created_at, received_at, rng.choice(REQUEST_DESCRIPTIONS), status,
            waiting_reason, preliminary_cost, total_cost, approved, approval_at,
            issued_at, completed_at,
        ))
    return rows


def fetch_available_request_ids(cursor: "psycopg.Cursor", table: str) -> list[int]:
    """Возвращает заявки, для которых ещё нет записи в diagnosis или активного назначения."""
    if table == "diagnosis":
        cursor.execute(
            "SELECT r.id FROM request r LEFT JOIN diagnosis d ON d.request_id = r.id "
            "WHERE d.id IS NULL ORDER BY r.id"
        )
    elif table == "master_assignment":
        cursor.execute(
            "SELECT r.id FROM request r LEFT JOIN master_assignment ma "
            "ON ma.request_id = r.id AND ma.is_active = TRUE "
            "WHERE ma.id IS NULL ORDER BY r.id"
        )
    else:
        raise ValueError(f"Неподдерживаемый тип таблицы для поиска заявок: {table}")
    return [int(row[0]) for row in cursor.fetchall()]


def generate_assignments(
    rng: random.Random, request_ids: Sequence[int], master_ids: Sequence[int], count: int
) -> list[tuple[object, ...]]:
    if count > len(request_ids):
        raise ValueError(
            f"Для {count} активных назначений доступны только {len(request_ids)} заявок без активного мастера."
        )
    if count and not master_ids:
        raise ValueError("Нельзя создать назначения: в employee нет сотрудников со специализацией 'Мастер'.")
    now = GENERATION_REFERENCE_TIME
    selected = rng.sample(list(request_ids), count)
    rows = []
    for request_id in selected:
        assigned_at = now - timedelta(days=rng.randint(0, 180), hours=rng.randint(0, 23))
        rows.append((request_id, rng.choice(master_ids), assigned_at, None, True))
    return rows


def generate_diagnoses(
    rng: random.Random, request_ids: Sequence[int], master_ids: Sequence[int], count: int
) -> list[tuple[object, ...]]:
    if count > len(request_ids):
        raise ValueError(
            f"Для {count} диагнозов доступны только {len(request_ids)} заявок без диагностики."
        )
    if count and not master_ids:
        raise ValueError("Нельзя создать диагностику: в employee нет сотрудников со специализацией 'Мастер'.")
    now = GENERATION_REFERENCE_TIME
    selected = rng.sample(list(request_ids), count)
    results = [
        ("Неисправность обнаружена, требуется ремонт", "Износ или отказ одного из компонентов"),
        ("Неисправность не подтверждена", None),
        ("Требуется дополнительная диагностика", "Недостаточно данных для точного определения причины"),
        ("Определена неисправность узла питания", "Проблема в цепи питания"),
    ]
    rows = []
    for request_id in selected:
        performed_at = now - timedelta(days=rng.randint(0, 90), hours=rng.randint(0, 23))
        result, malfunction = rng.choice(results)
        rows.append((request_id, rng.choice(master_ids), performed_at, result, malfunction))
    return rows


def generate_works(
    rng: random.Random, request_ids: Sequence[int], count: int
) -> list[tuple[object, ...]]:
    if count and not request_ids:
        raise ValueError("Нельзя создать работы без заявок.")
    now = GENERATION_REFERENCE_TIME
    rows = []
    for _ in range(count):
        status = rng.choice(WORK_STATUSES)
        started_at = now - timedelta(days=rng.randint(0, 120), hours=rng.randint(0, 23)) if rng.random() < 0.85 else None
        ended_at = None
        if status in ("Завершена", "Отменена") and started_at is not None:
            ended_at = min(now, started_at + timedelta(hours=rng.randint(1, 48)))
        rows.append((rng.choice(request_ids), started_at, ended_at, status, round(rng.uniform(0, 30000), 2)))
    return rows



REPAIR_STATUSES = ["Запланирован", "Выполняется", "Приостановлен", "Завершён", "Отменён"]
RESERVATION_STATUSES = ["Активен", "Использован", "Отменён"]
PAYMENT_METHODS = ["Карта", "Наличные", "Перевод"]
HISTORY_REASONS = ["Регистрация заявки", "Начало диагностики", "Согласование ремонта", "Завершение работ", "Выдача устройства"]
NOTIFICATION_EVENTS = ["REQUEST_CREATED", "STATUS_CHANGED", "DIAGNOSIS_READY", "REPAIR_APPROVAL", "REPAIR_COMPLETED", "DEVICE_READY", "PAYMENT_RECEIVED"]


def generate_repairs(rng: random.Random, work_ids: Sequence[int], master_ids: Sequence[int], count: int) -> list[tuple[object, ...]]:
    if count and not work_ids:
        raise ValueError("Нельзя создать ремонт без записей в work.")
    if count and not master_ids:
        raise ValueError("Нельзя создать ремонт: нет сотрудников со специализацией 'Мастер'.")
    now = GENERATION_REFERENCE_TIME
    rows = []
    for _ in range(count):
        status = rng.choice(REPAIR_STATUSES)
        started = now - timedelta(days=rng.randint(0, 90)) if rng.random() < 0.9 else None
        ended = None
        result = None
        if status in ("Завершён", "Отменён") and started is not None:
            ended = min(now, started + timedelta(hours=rng.randint(1, 72)))
        if status == "Завершён":
            result = rng.choice(["Устройство восстановлено", "Компонент заменён", "Работоспособность проверена"])
        rows.append((rng.choice(work_ids), rng.choice(master_ids), rng.choice(REQUEST_DESCRIPTIONS), round(rng.uniform(100, 40000), 2), result, started, ended, status))
    return rows


def generate_reservations(rng: random.Random, pairs: Sequence[tuple[int, int]], count: int) -> list[tuple[object, ...]]:
    if count and not pairs:
        raise ValueError("Для резервирования нужны свободные пары ремонт/запчасть.")
    # Передаются только пары, которые не конфликтуют с уже активными резервированиями.
    pairs = list(pairs)
    if count > len(pairs):
        raise ValueError(f"Для {count} резервирований доступны только {len(pairs)} пар ремонт/запчасть.")
    selected = rng.sample(pairs, count)
    now = GENERATION_REFERENCE_TIME
    rows = []
    for repair_id, part_id in selected:
        status = rng.choice(RESERVATION_STATUSES)
        rows.append((repair_id, part_id, rng.randint(1, 4), now - timedelta(days=rng.randint(0, 60)), status))
    return rows


def generate_used_parts(rng: random.Random, pairs: Sequence[tuple[int, int]], count: int) -> list[tuple[object, ...]]:
    if count and not pairs:
        raise ValueError("Для списания нужны свободные пары ремонт/запчасть.")
    pairs = list(pairs)
    if count > len(pairs):
        raise ValueError(f"Для {count} списаний доступны только {len(pairs)} пар ремонт/запчасть.")
    selected = rng.sample(pairs, count)
    now = GENERATION_REFERENCE_TIME
    return [(repair_id, part_id, rng.randint(1, 3), now - timedelta(days=rng.randint(0, 45))) for repair_id, part_id in selected]


def generate_payments(rng: random.Random, request_ids: Sequence[int], count: int) -> list[tuple[object, ...]]:
    if count > len(request_ids):
        raise ValueError(f"Нельзя создать {count} платежей: заявок доступно {len(request_ids)}.")
    selected = rng.sample(list(request_ids), count)
    now = GENERATION_REFERENCE_TIME
    rows = []
    for request_id in selected:
        amount = round(rng.uniform(100, 70000), 2) if rng.random() < 0.9 else 0
        status = "Оплачено" if amount > 0 else "Не требуется"
        paid_at = now - timedelta(days=rng.randint(0, 60)) if amount > 0 else None
        method = rng.choice(PAYMENT_METHODS) if amount > 0 else None
        rows.append((request_id, amount, paid_at, method, status))
    return rows


def generate_status_history(
    rng: random.Random, request_dates: Sequence[tuple[int, datetime]], count: int
) -> list[tuple[object, ...]]:
    """Создаёт историю с changed_at не раньше создания соответствующей заявки."""
    if count and not request_dates:
        raise ValueError("Нельзя создать историю статусов без заявок.")
    rows = []
    now = GENERATION_REFERENCE_TIME
    for _ in range(count):
        request_id, created_at = rng.choice(request_dates)
        new_status = weighted_choice(rng, REQUEST_STATUSES, [8, 12, 15, 15, 20, 12, 14, 4])
        old_status = rng.choice([status for status in REQUEST_STATUSES if status != new_status]) if rng.random() < 0.9 else None
        latest_offset = max(0, int((now - created_at).total_seconds()))
        elapsed_seconds = rng.randint(0, latest_offset) if latest_offset else 0
        changed_at = created_at + timedelta(seconds=elapsed_seconds)
        rows.append((request_id, old_status, new_status, rng.choice(HISTORY_REASONS), changed_at))
    return rows


def generate_notifications(rng: random.Random, request_ids: Sequence[int], count: int):
    """Yield notification rows lazily, so millions of rows are not held in RAM."""
    if count and not request_ids:
        raise ValueError("Нельзя создать уведомления без заявок.")
    now = GENERATION_REFERENCE_TIME
    delivery_statuses = ["Ожидает отправки", "Отправлено", "Ошибка"]
    for _ in range(count):
        yield (rng.choice(request_ids), rng.choice(NOTIFICATION_EVENTS), now - timedelta(days=rng.randint(0, 365), hours=rng.randint(0, 23)), rng.choice(delivery_statuses))


def insert_iterable(cursor: "psycopg.Cursor", table: str, columns: Sequence[str], rows, batch_size: int) -> int:
    """Пакетная вставка потока строк с возвратом количества; не накапливает весь поток."""
    columns_sql = ", ".join(f'"{column}"' for column in columns)
    placeholders = "(" + ", ".join(["%s"] * len(columns)) + ")"
    total = 0
    batch = []
    for row in rows:
        batch.append(row)
        if len(batch) >= batch_size:
            values_sql = ", ".join([placeholders] * len(batch))
            params = tuple(value for item in batch for value in item)
            cursor.execute(f'INSERT INTO "{table}" ({columns_sql}) VALUES {values_sql}', params)
            total += len(batch)
            batch.clear()
    if batch:
        values_sql = ", ".join([placeholders] * len(batch))
        params = tuple(value for item in batch for value in item)
        cursor.execute(f'INSERT INTO "{table}" ({columns_sql}) VALUES {values_sql}', params)
        total += len(batch)
    return total


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Генерация тестовых данных для БД сервисного центра (Sprint2).")
    parser.add_argument("--mode", choices=("custom", "development", "load"), default="custom", help="custom — количества задаются аргументами; development/load — готовые профили.")
    parser.add_argument("--seed", type=int, default=42, help="Seed генератора (по умолчанию 42).")
    parser.add_argument("--clients", type=int, default=100, help="Количество клиентов.")
    parser.add_argument("--employees", type=int, default=20, help="Количество сотрудников.")
    parser.add_argument("--equipment", type=int, default=300, help="Количество единиц оборудования.")
    parser.add_argument("--parts", type=int, default=50, help="Количество запчастей.")
    parser.add_argument("--requests", type=int, default=300, help="Количество заявок.")
    parser.add_argument("--assignments", type=int, default=0, help="Количество активных назначений мастеров.")
    parser.add_argument("--diagnoses", type=int, default=0, help="Количество записей диагностики.")
    parser.add_argument("--works", type=int, default=0, help="Количество работ.")
    parser.add_argument("--repairs", type=int, default=0, help="Количество ремонтов.")
    parser.add_argument("--reservations", type=int, default=0, help="Количество резервирований запчастей.")
    parser.add_argument("--used-parts", type=int, default=0, help="Количество списаний запчастей.")
    parser.add_argument("--payments", type=int, default=0, help="Количество платежей.")
    parser.add_argument("--history", type=int, default=0, help="Количество записей истории статусов.")
    parser.add_argument("--notifications", type=int, default=None, help="Количество уведомлений (в load режиме по умолчанию 3 млн).")
    parser.add_argument("--batch-size", type=int, default=1000, help="Размер пакета INSERT.")
    return parser.parse_args()


def validate_args(args: argparse.Namespace) -> None:
    if args.mode == "development":
        args.notifications = 100_000 if args.notifications is None else args.notifications
        # В режиме разработки крупнейшая таблица notification получает 100 тыс. строк.
        args.clients, args.employees, args.equipment, args.parts, args.requests = 100, 20, 300, 50, 300
        args.assignments, args.diagnoses, args.works, args.repairs = 100, 150, 250, 200
        args.reservations, args.used_parts, args.payments, args.history = 150, 100, 200, 1000
    elif args.mode == "load":
        args.notifications = 3_000_000 if args.notifications is None else args.notifications
        # Для нагрузочного профиля нужны только небольшие справочники и достаточно заявок.
        args.clients, args.employees, args.equipment, args.parts, args.requests = 100, 20, 300, 100, 1000
        args.assignments, args.diagnoses, args.works, args.repairs = 100, 150, 500, 400
        args.reservations, args.used_parts, args.payments, args.history = 200, 150, 500, 3000
    elif args.notifications is None:
        args.notifications = 0

    names = ("clients", "employees", "equipment", "parts", "requests", "assignments", "diagnoses", "works", "repairs", "reservations", "used_parts", "payments", "history", "notifications")
    for name in names:
        if getattr(args, name) < 0:
            raise ValueError(f"Параметр для {name} не может быть отрицательным.")
    if args.batch_size < 1:
        raise ValueError("Параметр --batch-size должен быть больше нуля.")
    if args.equipment > 0 and args.clients == 0:
        raise ValueError("При генерации оборудования нужны клиенты: --clients должен быть больше нуля.")


def main() -> int:
    args = parse_args()
    try:
        validate_args(args)
    except ValueError as error:
        print(f"Ошибка параметров: {error}", file=sys.stderr)
        return 2
    if psycopg is None:
        print('Не найден psycopg 3. Установи драйвер: python -m pip install "psycopg[binary]>=3.1,<4"', file=sys.stderr)
        return 2

    rng = random.Random(args.seed)
    connection_settings = {
        "host": os.getenv("PGHOST", "localhost"),
        "port": int(os.getenv("PGPORT", "5432")),
        "dbname": os.getenv("PGDATABASE", "service_center"),
        "user": os.getenv("PGUSER", "postgres"),
        "password": os.getenv("PGPASSWORD", "local_dev_password"),
    }

    try:
        with psycopg.connect(**connection_settings) as connection:
            with connection.cursor() as cursor:
                client_start = next_id_offset(cursor, "client")
                employee_start = next_id_offset(cursor, "employee")
                equipment_start = next_id_offset(cursor, "equipment")
                part_start = next_id_offset(cursor, "part")
                client_ids = insert_many(cursor, "client", ("full_name", "phone", "email"), generate_clients(rng, args.clients, client_start), args.batch_size)
                print(f"client: добавлено {len(client_ids)}")
                employee_ids = insert_many(cursor, "employee", ("full_name", "specialization", "phone", "email"), generate_employees(rng, args.employees, employee_start), args.batch_size)
                print(f"employee: добавлено {len(employee_ids)}")
                all_client_ids = fetch_ids(cursor, "client")
                equipment_ids = insert_many(cursor, "equipment", ("client_id", "type", "manufacturer", "model", "serial_number", "condition_description", "status"), generate_equipment(rng, all_client_ids, args.equipment, equipment_start), args.batch_size)
                print(f"equipment: добавлено {len(equipment_ids)}")
                part_ids = insert_many(cursor, "part", ("name", "article", "price", "stock_quantity"), generate_parts(rng, args.parts, part_start), args.batch_size)
                print(f"part: добавлено {len(part_ids)}")

                all_equipment_ids = fetch_ids(cursor, "equipment")
                cursor.execute("SELECT id FROM employee WHERE specialization = 'Оператор' ORDER BY id")
                operator_ids = [int(row[0]) for row in cursor.fetchall()]
                request_ids = insert_many(cursor, "request", ("equipment_id", "operator_id", "created_at", "received_at", "description", "status", "waiting_reason", "preliminary_cost", "total_cost", "client_approved", "approval_at", "issued_at", "completed_at"), generate_requests(rng, all_equipment_ids, operator_ids, args.requests), args.batch_size)
                print(f"request: добавлено {len(request_ids)}")
                all_request_ids = fetch_ids(cursor, "request")
                cursor.execute("SELECT id FROM employee WHERE specialization = 'Мастер' ORDER BY id")
                master_ids = [int(row[0]) for row in cursor.fetchall()]

                eligible_assignments = fetch_available_request_ids(cursor, "master_assignment")
                rows = generate_assignments(rng, eligible_assignments, master_ids, args.assignments)
                ids = insert_many(cursor, "master_assignment", ("request_id", "employee_id", "assigned_at", "ended_at", "is_active"), rows, args.batch_size)
                print(f"master_assignment: добавлено {len(ids)}")

                eligible_diagnoses = fetch_available_request_ids(cursor, "diagnosis")
                rows = generate_diagnoses(rng, eligible_diagnoses, master_ids, args.diagnoses)
                ids = insert_many(cursor, "diagnosis", ("request_id", "master_id", "performed_at", "result", "detected_malfunction"), rows, args.batch_size)
                print(f"diagnosis: добавлено {len(ids)}")

                work_ids = insert_many(cursor, "work", ("request_id", "started_at", "ended_at", "status", "cost"), generate_works(rng, all_request_ids, args.works), args.batch_size)
                print(f"work: добавлено {len(work_ids)}")
                all_work_ids = fetch_ids(cursor, "work")
                repair_rows = generate_repairs(rng, all_work_ids, master_ids, args.repairs)
                repair_ids = insert_many(cursor, "repair", ("work_id", "master_id", "description", "cost", "result", "started_at", "ended_at", "status"), repair_rows, args.batch_size)
                print(f"repair: добавлено {len(repair_ids)}")
                all_repair_ids = fetch_ids(cursor, "repair")
                all_part_ids = fetch_ids(cursor, "part")

                cursor.execute("SELECT r.id, p.id FROM repair r CROSS JOIN part p WHERE NOT EXISTS (SELECT 1 FROM part_reservation pr WHERE pr.repair_id = r.id AND pr.part_id = p.id AND pr.status = 'Активен') ORDER BY r.id, p.id")
                available_reservation_pairs = [(int(row[0]), int(row[1])) for row in cursor.fetchall()]
                rows = generate_reservations(rng, available_reservation_pairs, args.reservations)
                ids = insert_many(cursor, "part_reservation", ("repair_id", "part_id", "quantity", "reserved_at", "status"), rows, args.batch_size)
                print(f"part_reservation: добавлено {len(ids)}")
                cursor.execute("SELECT r.id, p.id FROM repair r CROSS JOIN part p WHERE NOT EXISTS (SELECT 1 FROM used_part up WHERE up.repair_id = r.id AND up.part_id = p.id) ORDER BY r.id, p.id")
                available_used_part_pairs = [(int(row[0]), int(row[1])) for row in cursor.fetchall()]
                rows = generate_used_parts(rng, available_used_part_pairs, args.used_parts)
                ids = insert_many(cursor, "used_part", ("repair_id", "part_id", "quantity", "written_off_at"), rows, args.batch_size)
                print(f"used_part: добавлено {len(ids)}")
                cursor.execute("SELECT r.id FROM request r LEFT JOIN payment p ON p.request_id = r.id WHERE p.id IS NULL ORDER BY r.id")
                requests_without_payment = [int(row[0]) for row in cursor.fetchall()]
                rows = generate_payments(rng, requests_without_payment, args.payments)
                ids = insert_many(cursor, "payment", ("request_id", "amount", "paid_at", "method", "status"), rows, args.batch_size)
                print(f"payment: добавлено {len(ids)}")
                cursor.execute("SELECT id, created_at FROM request ORDER BY id")
                request_dates = [(int(row[0]), row[1]) for row in cursor.fetchall()]
                rows = generate_status_history(rng, request_dates, args.history)
                ids = insert_many(cursor, "status_history", ("request_id", "old_status", "new_status", "reason", "changed_at"), rows, args.batch_size)
                print(f"status_history: добавлено {len(ids)}")
                count = insert_iterable(cursor, "notification", ("request_id", "event_type", "created_at", "delivery_status"), generate_notifications(rng, all_request_ids, args.notifications), args.batch_size)
                print(f"notification: добавлено {count}")
        print("Готово: транзакция успешно зафиксирована.")
        print(f"Режим: {args.mode}; seed: {args.seed}")
        return 0
    except ValueError as error:
        print(f"Ошибка генерации: {error}. Все вставки этой попытки отменены.", file=sys.stderr)
        return 2
    except psycopg.Error as error:
        print(f"Ошибка PostgreSQL; все вставки этой попытки отменены: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
