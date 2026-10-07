import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/database/app_database.dart';

import '../../generated_migrations/schema.dart';

/// Приводит SQL к единому виду: helper из снимка и drift в приложении
/// по-разному расставляют пробелы и кавычки, а смысл один.
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

const _accountCols =
    'id, name, icon_key, currency, opening_balance_minor, sort_order, '
    'created_at, updated_at';

void main() {
  late SchemaVerifier verifier;

  setUp(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('schema version 2', () {
    test('a fresh app database matches the version 2 snapshot', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 2);
    });

    test('CHECK constraints and partial indexes match the snapshot', () async {
      final schema = await verifier.schemaAt(2);
      final snapshotSql = {
        for (final row in schema.rawDatabase.select(_schemaQuery))
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

      const partialIndexes = {
        'accounts_order': 'WHERE deleted_at IS NULL',
        'transactions_account':
            'WHERE deleted_at IS NULL AND account_id IS NOT NULL',
        'transfers_occurred_on_at': 'WHERE deleted_at IS NULL',
        'transfers_from_account': 'WHERE deleted_at IS NULL',
        'transfers_to_account': 'WHERE deleted_at IS NULL',
      };
      partialIndexes.forEach((name, where) {
        expect(appSql[name], endsWith(where), reason: name);
      });
    });

    test('tables use only TEXT and INTEGER column types', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      for (final table in ['accounts', 'transfers', 'transactions']) {
        final rows = await db.customSelect('PRAGMA table_info($table)').get();
        for (final r in rows) {
          expect(
            r.read<String>('type'),
            anyOf('TEXT', 'INTEGER'),
            reason: '$table.${r.read<String>('name')}',
          );
        }
      }
    });

    test('accounts CHECK rejects bad currency, name and icon', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      Future<void> insert(String name, String icon, String currency) =>
          db.customStatement(
            'INSERT INTO accounts ($_accountCols) '
            "VALUES ('a', '$name', '$icon', '$currency', -500, 0, 1, 1)",
          );

      // Отрицательный остаток (долг) разрешён.
      await insert('Card', 'card', 'RUB');
      await db.customStatement('DELETE FROM accounts');
      await expectLater(insert('Card', 'card', 'rub'), throwsA(anything));
      await expectLater(insert('', 'card', 'RUB'), throwsA(anything));
      await expectLater(insert('N' * 41, 'card', 'RUB'), throwsA(anything));
      await expectLater(insert('Card', '', 'RUB'), throwsA(anything));
    });

    test('transfers CHECK and foreign keys reject bad rows', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      for (final id in ['a', 'b']) {
        await db.customStatement(
          'INSERT INTO accounts ($_accountCols) '
          "VALUES ('$id', 'N$id', 'card', 'RUB', 0, 0, 1, 1)",
        );
      }
      Future<void> insert({
        String from = 'a',
        String to = 'b',
        int amount = 100,
        String currency = 'RUB',
        String note = 'NULL',
      }) => db.customStatement(
        'INSERT INTO transfers (id, from_account_id, to_account_id, '
        'amount_minor, currency, occurred_on, occurred_at, note, created_at, '
        "updated_at) VALUES ('t', '$from', '$to', $amount, '$currency', "
        '20261007, 1, $note, 1, 1)',
      );

      // Корректная строка проходит.
      await insert();
      await db.customStatement('DELETE FROM transfers');
      await expectLater(insert(currency: 'rub'), throwsA(anything));
      await expectLater(insert(amount: 0), throwsA(anything));
      await expectLater(insert(to: 'a'), throwsA(anything));
      await expectLater(insert(note: "''"), throwsA(anything));
      await expectLater(insert(to: 'missing'), throwsA(anything));
    });

    test('an interrupted migration rolls back and can be retried', () async {
      final schema = await verifier.schemaAt(1);
      final raw = schema.rawDatabase;
      raw
        ..execute(
          'INSERT INTO categories (id, kind, name, icon_key, sort_order, '
          "created_at, updated_at) VALUES ('c1', 'expense', 'Food', 'food', "
          '0, 1, 1)',
        )
        // Индекс с тем же именем, что создаст миграция: она упадёт на нём
        // уже после создания таблиц и колонки.
        ..execute('CREATE INDEX transactions_account ON transactions (id)');
      expect(raw.select('PRAGMA user_version').single.values.single, 1);

      final broken = AppDatabase(schema.newConnection());
      await expectLater(
        broken.select(broken.categories).get(),
        throwsA(anything),
      );
      await broken.close();

      // Откат: версия прежняя, ни таблиц, ни колонки нет.
      expect(raw.select('PRAGMA user_version').single.values.single, 1);
      final tables = raw
          .select("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((r) => r['name'] as String);
      expect(tables, isNot(contains('accounts')));
      expect(tables, isNot(contains('transfers')));
      final columns = raw
          .select('PRAGMA table_info(transactions)')
          .map((r) => r['name'] as String);
      expect(columns, isNot(contains('account_id')));

      // Убираем помеху: повторное открытие мигрирует, данные на месте.
      raw.execute('DROP INDEX transactions_account');
      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 2);
      expect((await db.select(db.categories).get()).single.name, 'Food');
      expect(raw.select('PRAGMA user_version').single.values.single, 2);
    });

    test('migration v1 -> v2 keeps data and leaves account_id empty', () async {
      final schema = await verifier.schemaAt(1);
      schema.rawDatabase
        ..execute(
          "INSERT INTO app_settings (key, value, updated_at) VALUES ('theme', "
          "'dark', 42)",
        )
        ..execute(
          'INSERT INTO categories (id, kind, name, icon_key, parent_id, '
          'sort_order, archived_at, created_at, updated_at, deleted_at) '
          "VALUES ('c1', 'expense', 'Food', 'food', NULL, 0, NULL, 1, 2, "
          "NULL), ('c2', 'income', 'Salary', 'salary', NULL, 1, 33, 3, 4, "
          "NULL), ('s1', 'expense', 'Cafe', 'cafe', 'c1', 5, NULL, 6, 7, 8)",
        )
        ..execute(
          'INSERT INTO transactions (id, type, amount_minor, currency, '
          'occurred_on, occurred_at, category_id, subcategory_id, note, '
          'created_at, updated_at, deleted_at) VALUES '
          "('t1', 'expense', 12345, 'RUB', 20260920, 111, 'c1', 's1', "
          "'lunch', 5, 6, NULL), "
          "('t2', 'income', 0, 'RUB', 20260921, 222, 'c2', NULL, NULL, "
          '7, 8, 9)',
        );

      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 2);

      final rows = await db
          .customSelect('SELECT * FROM transactions ORDER BY id')
          .get();
      expect(rows, hasLength(2));
      expect(rows[0].data, {
        'id': 't1',
        'type': 'expense',
        'amount_minor': 12345,
        'currency': 'RUB',
        'occurred_on': 20260920,
        'occurred_at': 111,
        'category_id': 'c1',
        'subcategory_id': 's1',
        'note': 'lunch',
        'created_at': 5,
        'updated_at': 6,
        'deleted_at': null,
        'account_id': null,
      });
      expect(rows[1].data, {
        'id': 't2',
        'type': 'income',
        'amount_minor': 0,
        'currency': 'RUB',
        'occurred_on': 20260921,
        'occurred_at': 222,
        'category_id': 'c2',
        'subcategory_id': null,
        'note': null,
        'created_at': 7,
        'updated_at': 8,
        'deleted_at': 9,
        'account_id': null,
      });

      final categories = await db
          .customSelect('SELECT * FROM categories ORDER BY id')
          .get();
      expect(categories.map((r) => r.data), [
        {
          'id': 'c1',
          'kind': 'expense',
          'name': 'Food',
          'icon_key': 'food',
          'parent_id': null,
          'sort_order': 0,
          'archived_at': null,
          'created_at': 1,
          'updated_at': 2,
          'deleted_at': null,
        },
        {
          'id': 'c2',
          'kind': 'income',
          'name': 'Salary',
          'icon_key': 'salary',
          'parent_id': null,
          'sort_order': 1,
          'archived_at': 33,
          'created_at': 3,
          'updated_at': 4,
          'deleted_at': null,
        },
        {
          'id': 's1',
          'kind': 'expense',
          'name': 'Cafe',
          'icon_key': 'cafe',
          'parent_id': 'c1',
          'sort_order': 5,
          'archived_at': null,
          'created_at': 6,
          'updated_at': 7,
          'deleted_at': 8,
        },
      ]);
      final settings = await db
          .customSelect('SELECT * FROM app_settings')
          .get();
      expect(settings.single.data, {
        'key': 'theme',
        'value': 'dark',
        'updated_at': 42,
      });
      expect(await db.select(db.accounts).get(), isEmpty);
      expect(await db.select(db.transfers).get(), isEmpty);

      final fk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(fk, isEmpty);
    });
  });
}
