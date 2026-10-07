import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

// Относительный импорт: сгенерированный помощник лежит в test/, а не в lib/,
// поэтому package:-путь к нему невозможен.
import '../../generated_migrations/schema.dart';

/// Приводит SQL к единому виду: один пробел вместо любого числа пробелов и
/// переносов, без пробелов вокруг скобок и без кавычек у имён.
String _normalize(String sql) => sql
    .replaceAll('"', '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r' ?\( ?'), '(')
    .replaceAll(RegExp(r' ?\) ?'), ')')
    .trim();

const _schemaQuery =
    'SELECT name, sql FROM sqlite_master '
    "WHERE type IN ('table', 'index') AND sql IS NOT NULL "
    "AND name NOT LIKE 'sqlite_%' ORDER BY name";

/// Выпущенная схема v1, зашитая в тест (в нормализованном виде). Её менять
/// нельзя никогда: любая правка таблиц - только миграция.
const _expectedV1 = <String, String>{
  'app_settings':
      'CREATE TABLE app_settings(key TEXT NOT NULL, value TEXT NOT NULL, '
      'updated_at INTEGER NOT NULL, PRIMARY KEY(key))',
  'categories':
      'CREATE TABLE categories(id TEXT NOT NULL, kind TEXT NOT NULL, '
      'name TEXT NOT NULL, icon_key TEXT NOT NULL, '
      'parent_id TEXT NULL REFERENCES categories(id), '
      'sort_order INTEGER NOT NULL, archived_at INTEGER NULL, '
      'created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, '
      'deleted_at INTEGER NULL, PRIMARY KEY(id), '
      "CHECK(kind IN('income', 'expense')))",
  'categories_kind_level_order':
      'CREATE INDEX categories_kind_level_order ON '
      'categories(kind, parent_id, sort_order)WHERE deleted_at IS NULL',
  'categories_level_order':
      'CREATE INDEX categories_level_order ON '
      'categories(parent_id, sort_order)WHERE deleted_at IS NULL',
  'transactions':
      'CREATE TABLE transactions(id TEXT NOT NULL, type TEXT NOT NULL, '
      'amount_minor INTEGER NOT NULL, currency TEXT NOT NULL, '
      'occurred_on INTEGER NOT NULL, occurred_at INTEGER NOT NULL, '
      'category_id TEXT NOT NULL REFERENCES categories(id), '
      'subcategory_id TEXT NULL REFERENCES categories(id), note TEXT NULL, '
      'created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, '
      'deleted_at INTEGER NULL, PRIMARY KEY(id), '
      "CHECK(type IN('income', 'expense')), CHECK(amount_minor >= 0), "
      "CHECK(currency GLOB '[A-Z][A-Z][A-Z]'), "
      'CHECK(occurred_on BETWEEN 10101 AND 99991231), '
      'CHECK(note IS NULL OR length(note)BETWEEN 1 AND 200))',
  'transactions_category_occurred_on':
      'CREATE INDEX transactions_category_occurred_on ON '
      'transactions(category_id, occurred_on)WHERE deleted_at IS NULL',
  'transactions_occurred_on_at':
      'CREATE INDEX transactions_occurred_on_at ON '
      'transactions(occurred_on, occurred_at)WHERE deleted_at IS NULL',
};

/// Схема v1 выпущена и неизменна. Приложение теперь на v2, поэтому «свежая
/// база = снимок» проверяется в `schema_v2_test.dart`, а здесь - что снимок v1
/// остался прежним (он нужен тесту миграции v1 -> v2).
void main() {
  test('the version 1 snapshot still describes the released schema', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(1);

    final snapshotSql = {
      for (final row in schema.rawDatabase.select(_schemaQuery))
        row['name'] as String: _normalize(row['sql'] as String),
    };
    expect(snapshotSql.keys, unorderedEquals(_expectedV1.keys));
    expect(snapshotSql, _expectedV1);

    final columns = schema.rawDatabase
        .select('PRAGMA table_info(transactions)')
        .map((r) => r['name'] as String);
    expect(columns, isNot(contains('account_id')));
    expect(columns, hasLength(12));
  });
}
