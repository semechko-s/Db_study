# Makefile для базы данных service_center
# Миграциями управляет golang-migrate.
ifneq (,$(wildcard .env))
include .env
export
endif

.DEFAULT_GOAL := help


DB             ?= service_center
PSQL_USER      ?= service_migrator
PSQL_HOST      ?= localhost
PSQL_PORT      ?= 5432
MIGRATOR_PASSWORD ?= $(MIGRATOR_PASSWORD)
DATABASE_URL   = postgres://$(PSQL_USER):$(MIGRATOR_PASSWORD)@$(PSQL_HOST):$(PSQL_PORT)/$(DB)?sslmode=disable

MIGRATIONS_DIR := migrations
TEST_DIR       := test

export PGPASSWORD := $(MIGRATOR_PASSWORD)

PSQL := psql -v ON_ERROR_STOP=1 -U $(PSQL_USER) -h $(PSQL_HOST) -p $(PSQL_PORT) -d $(DB)


.PHONY: help up down down-all version force redo createdb dropdb test-data test full-check


help: ## Показать список доступных команд
	@echo ""
	@echo "============================================"
	@echo "       Service Center - Database"
	@echo "============================================"
	@echo ""
	@echo "Перед использованием Makefile необходимо заполнить файл .env"
	@echo ""
	@echo "Использование:"
	@echo "  make <команда>"
	@echo ""
	@echo "Доступные команды:"
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "} {printf "  %-14s %s\n", $$1, $$2}'
	@echo ""
	@echo "Настройки можно переопределить:"
	@echo "  make up PSQL_USER=имя DB=имя_базы"
	@echo ""


up: createdb ## Создать базу при необходимости и применить миграции
	migrate -path $(MIGRATIONS_DIR) -database "$(DATABASE_URL)" up

down: ## Откатить одну последнюю миграцию
	migrate -path $(MIGRATIONS_DIR) -database "$(DATABASE_URL)" down 1

down-all: ## Откатить все миграции
	@set -eu; \
	exists=$$(psql -X -w -U $(PSQL_USER) -h $(PSQL_HOST) -p $(PSQL_PORT) -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$(DB)'"); \
	if [ "$$exists" != "1" ]; then \
		echo "База $(DB) не существует. Откатывать нечего."; \
		exit 0; \
	fi; \
	migrate -path $(MIGRATIONS_DIR) -database "$(DATABASE_URL)" down

version: ## Показать текущую версию схемы
	migrate -path $(MIGRATIONS_DIR) -database "$(DATABASE_URL)" version

force: ## Принудительно установить версию (make force VERSION=N)
	@test -n "$(VERSION)" || (echo "Ошибка: укажи VERSION=N"; exit 1)
	migrate -path $(MIGRATIONS_DIR) -database "$(DATABASE_URL)" force $(VERSION)

redo: ## Откатить все миграции и применить заново
	$(MAKE) down-all
	$(MAKE) up

# -------------------- База данных ---------------------------

createdb: ## Создать базу данных, если её ещё нет
	@set -eu; \
	exists=$$(psql -X -w -U $(PSQL_USER) -h $(PSQL_HOST) -p $(PSQL_PORT) -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$(DB)'"); \
	if [ "$$exists" = "1" ]; then \
		echo "База $(DB) уже существует"; \
	else \
		echo "Создание базы $(DB)..."; \
		createdb -w -U $(PSQL_USER) -h $(PSQL_HOST) -p $(PSQL_PORT) $(DB) || { \
			echo "Ошибка создания базы $(DB). Проверь права пользователя."; \
			exit 1; \
		}; \
	fi

dropdb: ## Удалить базу данных
	dropdb -U $(PSQL_USER) -h $(PSQL_HOST) -p $(PSQL_PORT) $(DB)
