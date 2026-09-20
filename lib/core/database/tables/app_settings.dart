import 'package:drift/drift.dart';

/// Таблица настроек приложения: пары «ключ — значение» (SQL-имя `app_settings`).
///
/// Колонки: `key` (текст, первичный ключ), `value` (текст),
/// `updated_at` (целое число: миллисекунды эпохи UTC, ADR 0001).
class AppSettings extends Table {
  TextColumn get key => text()();

  TextColumn get value => text()();

  // Именно int, а не DateTime-колонка drift: в базе хранится целое число.
  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
