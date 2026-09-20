import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/database/app_database.dart';

// Относительный импорт: сгенерированный помощник лежит в test/, а не в lib/,
// поэтому package:-путь к нему невозможен.
import '../../generated_migrations/schema.dart';

/// Приводит SQL к единому виду: один пробел вместо любого числа пробелов и
/// переносов, без пробелов вокруг скобок и без кавычек у имён. Нужно потому,
/// что helper из снимка пишет `PRIMARY KEY ("id")`, а drift в приложении —
/// `PRIMARY KEY(id)`: смысл один, раскладка разная. Одинаково обработанные
/// обе стороны сравниваются честно, а CHECK и WHERE остаются в тексте.
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

void main() {
  late SchemaVerifier verifier;

  setUp(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('schema version 1', () {
    test('a fresh app database matches the version 1 snapshot', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // Бросает SchemaMismatch с описанием расхождения, если база приложения
      // отличается от снимка drift_schemas/drift_schema_v1.json.
      await verifier.migrateAndValidate(db, 1);
    });

    test('CHECK constraints and partial indexes match the snapshot', () async {
      // Снимок хранит тексты CHECK и частичных индексов, поэтому их можно
      // сравнить напрямую: свежая база приложения против базы из снимка.
      final schema = await verifier.schemaAt(1);
      final snapshotRows = schema.rawDatabase.select(_schemaQuery);
      final snapshotSql = {
        for (final row in snapshotRows)
          row['name'] as String: _normalize(row['sql'] as String),
      };

      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final appRows = await db.customSelect(_schemaQuery).get();
      final appSql = {
        for (final row in appRows)
          row.read<String>('name'): _normalize(row.read<String>('sql')),
      };

      expect(appSql.keys, unorderedEquals(snapshotSql.keys));
      expect(appSql, snapshotSql);

      // Защита от пустого сравнения: нужные фрагменты действительно есть.
      expect(
        appSql['categories'],
        contains(_normalize("CHECK (kind IN ('income', 'expense'))")),
      );
      for (final check in [
        "CHECK (type IN ('income', 'expense'))",
        'CHECK (amount_minor >= 0)',
        'CHECK (length(currency) = 3)',
        'CHECK (note IS NULL OR length(note) <= 200)',
      ]) {
        expect(appSql['transactions'], contains(_normalize(check)));
      }
      const partialIndexes = [
        'categories_level_order',
        'categories_kind_level_order',
        'transactions_occurred_on',
        'transactions_category_occurred_on',
      ];
      for (final name in partialIndexes) {
        expect(
          appSql[name],
          endsWith('WHERE deleted_at IS NULL'),
          reason: name,
        );
      }
    });

    test('data written into a version 1 database survives opening', () async {
      // Образец теста миграции «база версии N -> код -> данные на месте».
      // Сейчас версия одна, поэтому «миграции» нет и открываем v1 как есть;
      // при появлении v2 меняются startAt(1) -> migrateAndValidate(db, 2).
      final schema = await verifier.schemaAt(1);
      schema.rawDatabase
        ..execute(
          'INSERT INTO categories (id, kind, name, icon_key, sort_order, '
          "created_at, updated_at) VALUES ('c1', 'expense', 'Food', 'food', "
          '0, 1, 1)',
        )
        ..execute(
          'INSERT INTO transactions (id, type, amount_minor, currency, '
          'occurred_on, occurred_at, category_id, created_at, updated_at) '
          "VALUES ('t1', 'expense', 12345, 'RUB', 20260920, 1, 'c1', 1, 1)",
        );

      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 1);

      final categories = await db.select(db.categories).get();
      expect(categories.single.name, 'Food');
      final transactions = await db.select(db.transactions).get();
      expect(transactions.single.amountMinor, 12345);
      expect(transactions.single.categoryId, 'c1');
    });
  });
}
