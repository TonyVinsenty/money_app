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

    test('migration v1 -> v2 keeps data and leaves account_id empty', () async {
      final schema = await verifier.schemaAt(1);
      schema.rawDatabase
        ..execute(
          'INSERT INTO categories (id, kind, name, icon_key, sort_order, '
          "created_at, updated_at) VALUES ('c1', 'expense', 'Food', 'food', "
          "0, 1, 1), ('c2', 'income', 'Salary', 'salary', 1, 1, 1)",
        )
        ..execute(
          'INSERT INTO categories (id, kind, name, icon_key, parent_id, '
          "sort_order, created_at, updated_at) VALUES ('s1', 'expense', "
          "'Cafe', 'cafe', 'c1', 0, 1, 1)",
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
      final t1 = rows[0].data;
      expect(t1['type'], 'expense');
      expect(t1['amount_minor'], 12345);
      expect(t1['currency'], 'RUB');
      expect(t1['occurred_on'], 20260920);
      expect(t1['occurred_at'], 111);
      expect(t1['category_id'], 'c1');
      expect(t1['subcategory_id'], 's1');
      expect(t1['note'], 'lunch');
      expect(t1['created_at'], 5);
      expect(t1['updated_at'], 6);
      expect(t1['deleted_at'], isNull);
      final t2 = rows[1].data;
      expect(t2['type'], 'income');
      expect(t2['amount_minor'], 0);
      expect(t2['note'], isNull);
      expect(t2['deleted_at'], 9);
      expect(rows.map((r) => r.data['account_id']), everyElement(isNull));

      expect(await db.select(db.categories).get(), hasLength(3));
      expect(await db.select(db.accounts).get(), isEmpty);
      expect(await db.select(db.transfers).get(), isEmpty);

      final fk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(fk, isEmpty);
    });
  });
}
