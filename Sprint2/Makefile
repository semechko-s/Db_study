# Makefile для миграций базы данных "service_center" (Sprint2)
#
# Каждая цель up-NNN / down-NNN перед запуском файла спрашивает реестр
# schema_migrations: применена ли уже эта версия. Если да — пропускает
# запуск вместо того, чтобы упасть на "relation already exists". Если
# реестра ещё нет (совсем пустая база) — запрос просто не находит строку,
# и миграция 001 создаёт реестр сама первой же командой внутри своей
# транзакции.
#
# Использование:
#   make up            — применить все миграции по порядку (001 -> 002)
#   make down          — откатить все миграции в обратном порядке (002 -> 001)
#   make up-001        — применить только миграцию 001 (пропустит, если уже применена)
#   make up-002        — применить только миграцию 002 (пропустит, если уже применена)
#   make down-002      — откатить только миграцию 002 (пропустит, если не применена)
#   make down-001      — откатить только миграцию 001 (пропустит, если не применена)
#   make redo          — down + up (пересоздать схему с нуля)
#   make status        — показать, какие версии сейчас отмечены применёнными
#   make createdb      — создать базу $(DB)
#   make dropdb        — удалить базу $(DB)
#   make test-data     — createdb + up + загрузить test/test_data.sql (в чистую базу)
#   make test          — createdb + up + прогнать test/automated_constraint_checks.sql
#                         (сам тестовый скрипт всё откатывает через ROLLBACK,
#                          поэтому после него база остаётся пустой — только со схемой)
#   make full-check    — test-data, затем test поверх тех же данных, затем dropdb
#
# Переменные можно переопределить при вызове, например:
#   make up DB=my_test_db PSQL_USER=postgres

DB           ?= service_center
PSQL_USER    ?= $(USER)
PSQL_HOST    ?= localhost
PSQL_PORT    ?= 5432

MIGRATIONS_DIR := migrations
TEST_DIR       := test

PSQL := psql -v ON_ERROR_STOP=1 -U $(PSQL_USER) -h $(PSQL_HOST) -p $(PSQL_PORT) -d $(DB)

# Проверить, применена ли версия. Печатает "1", если да, иначе пусто.
# 2>/dev/null глушит ошибку "relation schema_migrations does not exist"
# на самой первой, ещё пустой базе — это не сбой, а нормальное "нет, не применена".
CHECK_APPLIED = $(PSQL) -tAc "SELECT 1 FROM schema_migrations WHERE version='$(1)'" 2>/dev/null

.PHONY: up down up-001 up-002 down-001 down-002 redo status createdb dropdb \
        test-data test full-check

## Применить все миграции по порядку: сначала схема, потом ограничения/индексы
up: up-001 up-002

up-001:
	@applied=$$($(call CHECK_APPLIED,001)); \
	if [ "$$applied" = "1" ]; then \
		echo "001 уже применена, пропускаю"; \
	else \
		$(PSQL) -f $(MIGRATIONS_DIR)/001_create_base_schema.up.sql; \
	fi

up-002:
	@applied=$$($(call CHECK_APPLIED,002)); \
	if [ "$$applied" = "1" ]; then \
		echo "002 уже применена, пропускаю"; \
	else \
		base=$$($(call CHECK_APPLIED,001)); \
		if [ "$$base" != "1" ]; then \
			echo "Ошибка: миграция 001 ещё не применена, сначала make up-001"; \
			exit 1; \
		fi; \
		$(PSQL) -f $(MIGRATIONS_DIR)/002_add_constraints_and_indexes.up.sql; \
	fi

## Откатить все миграции в обратном порядке: сначала ограничения/индексы, потом схема
down: down-002 down-001

down-002:
	@applied=$$($(call CHECK_APPLIED,002)); \
	if [ "$$applied" = "1" ]; then \
		$(PSQL) -f $(MIGRATIONS_DIR)/002_add_constraints_and_indexes.down.sql; \
	else \
		echo "002 не применена, пропускаю откат"; \
	fi

down-001:
	@applied=$$($(call CHECK_APPLIED,001)); \
	if [ "$$applied" = "1" ]; then \
		$(PSQL) -f $(MIGRATIONS_DIR)/001_create_base_schema.down.sql; \
	else \
		echo "001 не применена, пропускаю откат"; \
	fi

## Полное пересоздание схемы: откатить всё и накатить заново
redo: down up

## Показать текущее состояние реестра миграций
status:
	@$(PSQL) -c "SELECT version, applied_at FROM schema_migrations ORDER BY version" \
		2>/dev/null || echo "schema_migrations ещё не создан — ни одна миграция не применена"

createdb:
	createdb -U $(PSQL_USER) -h $(PSQL_HOST) -p $(PSQL_PORT) $(DB)

dropdb:
	dropdb -U $(PSQL_USER) -h $(PSQL_HOST) -p $(PSQL_PORT) $(DB)

## пересоздать базу с нуля, накатить схему и загрузить тестовые данные
test-data:
	-$(MAKE) dropdb 2>/dev/null
	$(MAKE) createdb
	$(MAKE) up
	$(PSQL) -f $(TEST_DIR)/test_data.sql

## пересоздать базу с нуля, накатить схему и прогнать автотесты ограничений
## (скрипт сам всё оборачивает в BEGIN...ROLLBACK, база после него пустая)
test:
	-$(MAKE) dropdb 2>/dev/null
	$(MAKE) createdb
	$(MAKE) up
	$(PSQL) -f $(TEST_DIR)/automated_constraint_checks.sql

##cхема + тестовые данные + автотесты поверх них в одной базе
full-check:
	-$(MAKE) dropdb 2>/dev/null
	$(MAKE) createdb
	$(MAKE) up
	$(PSQL) -f $(TEST_DIR)/test_data.sql
	$(PSQL) -f $(TEST_DIR)/automated_constraint_checks.sql
	$(MAKE) dropdb