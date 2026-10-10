# Как добавить миграцию схемы базы

Миграция — это код, который переводит уже существующую базу на устройстве пользователя
со схемы версии N на N+1 (добавить колонку, таблицу, индекс) и не теряет его данные.
«Снимок» схемы — файл `drift_schemas/drift_schema_vN.json`: точная копия схемы версии N.
По нему тесты строят настоящую базу «как была в версии N» и сверяют с ней приложение.

Настоящая миграция v1 -> v2 сделана на этапе 5 (счета и переводы, ADR 0010) и выпущена
(сборка 0.1.0+17 на iPhone). Образец тестов — `test/core/database/schema_v2_test.dart`:
«свежая база = снимок v2», `CHECK` и индексы, тест `migration v1 -> v2 keeps data and leaves
account_id empty` (данные v1 переживают миграцию) и `an interrupted migration rolls back and can
be retried` (миграция в одной транзакции). Тест схемы v1 — `test/core/database/schema_v1_test.dart`.

## Порядок

1. **Изменить таблицу и поднять версию.** Правим файл в `lib/core/database/tables/`
   (новую колонку делаем `nullable()` или с `withDefault`, иначе старые строки не заполнятся)
   и увеличиваем `schemaVersion` в `lib/core/database/app_database.dart` на 1.
2. **Перегенерировать код drift:**
   `dart run build_runner build`
3. **Выгрузить снимок новой версии** (старые снимки НЕ трогаем и не удаляем):
   `dart run drift_dev schema dump lib/core/database/app_database.dart drift_schemas/`
   Появится `drift_schema_v2.json`. Повторный запуск файл не меняет.
4. **Перегенерировать помощников для тестов:**
   `dart run drift_dev schema generate drift_schemas/ test/generated_migrations/`
   Файлы в `test/generated_migrations/` коммитим, руками не правим.
5. **Написать шаг миграции** в `MigrationStrategy.onUpgrade` (в `app_database.dart`), например
   `if (from < 2) { await m.addColumn(categories, categories.newColumn); }`.
   Затем тест «база версии 1 -> миграция -> версия 2, данные на месте»:
   `schema = await verifier.schemaAt(1)`, вставить строки через `schema.rawDatabase.execute(...)`,
   открыть `AppDatabase(schema.newConnection())`, вызвать `verifier.migrateAndValidate(db, 2)`
   и прочитать данные (образец — тест `migration v1 -> v2 keeps data and leaves account_id empty`
   в `schema_v2_test.dart`).
6. **Обновить тест схемы версии 1 не нужно:** он проверяет именно v1 по снимку v1.
   Добавьте аналогичный `schema_v2_test.dart` («свежая база = снимок v2»).

## Перед коммитом

- `dart format .`, `flutter analyze` (без замечаний), `flutter test` (зелёный).
- В `git status` есть: новый `drift_schema_vN.json`, обновлённые `app_database.g.dart` и
  `test/generated_migrations/`, тест миграции. Старые снимки не изменились.
- Если тест схемы падает с `Schema does not match` — таблицы в коде и снимок расходятся:
  вы забыли шаг 3 или 4, либо `onUpgrade` даёт схему, отличную от свежей базы.
- Если менялись CHECK или частичные индексы, убедитесь, что тест
  `CHECK constraints and partial indexes match the snapshot` зелёный.
- Нельзя править уже выпущенный снимок: пользователи могут иметь базу этой версии.
