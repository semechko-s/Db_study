# Безопасность: роли и секреты

## Роли

| Роль | Назначение | Суперпользователь |
|---|---|:-:|
| `service_admin` | администратор проекта: полный доступ к данным | нет |
| `service_app` | подключение приложения: только работа с данными | нет |
| `service_analyst` | аналитика: только чтение | нет |
| `service_migrator` | применение миграций: создаёт и меняет схему, владеет таблицами проекта | нет |

Приложение не должно подключаться как суперпользователь.
Роли создаются скриптом `01_roles.sql`, пароли в нём не задаются.

## Матрица прав

Проверено скриптом `02_role_permissions_demo.sql`, результат в `demo_result.txt`.

| Операция | service_admin | service_app | service_analyst | service_migrator |
|---|:-:|:-:|:-:|:-:|
| SELECT | ✅ | ✅ | ✅ | свои таблицы |
| INSERT / UPDATE / DELETE | ✅ | ✅ | ❌ | свои таблицы |
| TRUNCATE | ✅ | ❌ | ❌ | свои таблицы |
| CREATE TABLE в `public` | ✅ | ❌ | ❌ | ✅ |
| ALTER / DROP таблиц проекта | ❌ | ❌ | ❌ | ✅ (владелец) |
| Выдача членства в ролях (GRANT роли) | ❌ | ❌ | ❌ | ❌ |
| CREATE ROLE | ❌ | ❌ | ❌ | ❌ |
| Чтение `pg_authid` (хеши паролей) | ❌ | ❌ | ❌ | ❌ |

Права на новые таблицы, которые создаёт `service_migrator`, выдаются автоматически
(`ALTER DEFAULT PRIVILEGES` в `01_roles.sql`):

| Роль | Новые таблицы | Новые последовательности |
|---|---|---|
| `service_admin` | ALL | ALL |
| `service_app` | SELECT, INSERT, UPDATE, DELETE | USAGE, SELECT |
| `service_analyst` | SELECT | нет |

Примечание: у `service_migrator` есть атрибут `CREATEDB`.

## Установка с нуля

Шаги 1–3 выполняет суперпользователь. Префикс `env -u PGPASSWORD` убирает из окружения пароль `service_migrator`,
чтобы он не уходил под именем суперпользователя.

1. Создать базу:
   ```bash
   env -u PGPASSWORD createdb -U <суперпользователь> service_center
   ```
2. Создать роли и выдать права:
   ```bash
   env -u PGPASSWORD psql -U <суперпользователь> -d service_center -f security/01_roles.sql
   ```
3. Задать пароли интерактивно, чтобы они не попали в файлы и историю shell:
   ```bash
   env -u PGPASSWORD psql -U <суперпользователь> -d service_center
   ```
   ```
   \password service_admin
   \password service_app
   \password service_analyst
   \password service_migrator
   \q
   ```
   Для каждой роли используйте свой длинный случайный пароль.
4. Скопировать шаблон и заполнить `.env`:
   ```bash
   cp .env.example .env
   chmod 600 .env
   ```
5. Применить миграции:
   ```bash
   make up
   ```
6. Загрузить тестовые данные:
   ```bash
   set -a; source .env; set +a
   python3 scripts/generate_data.py --seed 42
   ```

```bashenv -u PGPASSWORD psql -U <суперпользователь> -d service_center \
  -f security/02_role_permissions_demo.sql | tee security/demo_result.txt
```

Результат последнего прогона: 42 проверки, 42 совпало, 0 несоответствий.
Если ролей `service_*` в базе нет, сначала выполните `01_roles.sql`.
