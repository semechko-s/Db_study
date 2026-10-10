# Makefile для базы данных service_center
# Миграциями управляет golang-migrate.

DB           ?= service_center
PSQL_USER    ?= $(USER)
PSQL_HOST    ?= localhost
PSQL_PORT    ?= 5432

DATABASE_URL := postgres://$(PSQL_USER)@$(PSQL_HOST):$(PSQL_PORT)/$(DB)?sslmode=disable
MIGRATIONS_DIR := migrations
TEST_DIR := test
PSQL := psql -v ON_ERROR_STOP=1 -U $(PSQL_USER) -h $(PSQL_HOST) -p $(PSQL_PORT) -d $(DB)

.PHONY: up down down-all version force redo createdb dropdb test-data test full-check

# Применить все доступные миграции.
up:
	migrate -path $(MIGRATIONS_DIR) -database "$(DATABASE_URL)" up

# Откатить одну последнюю миграцию.
down:
	migrate -path $(MIGRATIONS_DIR) -database "$(DATABASE_URL)" down 1

# Откатить все миграции.
down-all:
	migrate -path $(MIGRATIONS_DIR) -database "$(DATABASE_URL)" down

# Показать текущую версию схемы.
version:
	migrate -path $(MIGRATIONS_DIR) -database "$(DATABASE_URL)" version

# Принудительно установить номер версии (использовать только для восстановления состояния).
force:
	migrate -path $(MIGRATIONS_DIR) -database "$(DATABASE_URL)" force $(VERSION)

# Полностью пересоздать схему.
redo: down-all up

# Создать базу данных.
createdb:
	createdb -U $(PSQL_USER) -h $(PSQL_HOST) -p $(PSQL_PORT) $(DB)

# Удалить базу данных.
dropdb:
	dropdb -U $(PSQL_USER) -h $(PSQL_HOST) -p $(PSQL_PORT) $(DB)
