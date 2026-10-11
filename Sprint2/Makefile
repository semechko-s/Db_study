# Makefile для базы данных service_center
# Миграциями управляет golang-migrate.
ifneq (,$(wildcard .env))
include .env
export
endif

.DEFAULT_GOAL := help


DB             ?= service_center
PSQL_USER      ?= $(USER)
PSQL_HOST      ?= localhost
PSQL_PORT      ?= 5432

DATABASE_URL   = postgres://$(PSQL_USER)@$(PSQL_HOST):$(PSQL_PORT)/$(DB)?sslmode=disable

MIGRATIONS_DIR := migrations
TEST_DIR       := test

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
	@createdb -U $(PSQL_USER) -h $(PSQL_HOST) -p $(PSQL_PORT) $(DB) 2>/dev/null || \
		$(PSQL) -tAc "SELECT 1" >/dev/null 2>&1 || \
		(echo "Ошибка подключения к PostgreSQL или создания базы $(DB)"; exit 1)

dropdb: ## Удалить базу данных
	dropdb -U $(PSQL_USER) -h $(PSQL_HOST) -p $(PSQL_PORT) $(DB)
