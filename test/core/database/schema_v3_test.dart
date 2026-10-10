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
    'id, name, icon_key, currency, currency_digits, opening_balance_minor, '
    'sort_order, created_at, updated_at';

void main() {
  late SchemaVerifier verifier;

  setUp(() {
    verifier = SchemaVerifier(GeneratedHelper());
  });

  group('schema version 3', () {
    test('a fresh app database matches the version 3 snapshot', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 3);
    });

    test('CHECK constraints and partial indexes match the snapshot', () async {
      final schema = await verifier.schemaAt(3);
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
        'recurring_dues_transaction': 'WHERE transaction_id IS NOT NULL',
      };
      partialIndexes.forEach((name, where) {
        expect(appSql[name], endsWith(where), reason: name);
      });
    });

    test('tables use only TEXT and INTEGER column types', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      for (final table in [
        'accounts',
        'transfers',
        'transactions',
        'recurring_payments',
        'recurring_dues',
      ]) {
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
      Future<void> insert(
        String name,
        String icon,
        String currency, {
        int digits = 2,
      }) => db.customStatement(
        'INSERT INTO accounts ($_accountCols) '
        "VALUES ('a', '$name', '$icon', '$currency', $digits, -500, 0, 1, 1)",
      );

      // Отрицательный остаток (долг) разрешён.
      await insert('Card', 'card', 'RUB');
      await db.customStatement('DELETE FROM accounts');
      // Длинные коды и цифры в коде (не первой) разрешены.
      for (final ok in ['USDT', 'TON', 'BTC2', 'ABCDEFGHIJ']) {
        await insert('Card', 'card', ok);
        await db.customStatement('DELETE FROM accounts');
      }
      for (final bad in [
        'rub',
        'usdt',
        'US',
        '1BTC',
        'US-D',
        'AB CD',
        'ABCDEFGHIJK', // 11 символов
        '',
      ]) {
        await expectLater(
          insert('Card', 'card', bad),
          throwsA(anything),
          reason: 'code "$bad"',
        );
      }
      // Знаки валюты: 0 и 8 можно, -1 и 9 нельзя.
      for (final ok in [0, 8]) {
        await insert('Card', 'card', 'RUB', digits: ok);
        await db.customStatement('DELETE FROM accounts');
      }
      for (final bad in [-1, 9]) {
        await expectLater(
          insert('Card', 'card', 'RUB', digits: bad),
          throwsA(anything),
          reason: 'digits $bad',
        );
      }
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
          "VALUES ('$id', 'N$id', 'card', 'RUB', 2, 0, 0, 1, 1)",
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
      await insert(currency: 'USDT');
      await db.customStatement('DELETE FROM transfers');
      for (final bad in ['rub', 'usdt', 'US', '1BTC', 'US-D', 'ABCDEFGHIJK']) {
        await expectLater(
          insert(currency: bad),
          throwsA(anything),
          reason: 'code "$bad"',
        );
      }
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
      await verifier.migrateAndValidate(db, 3);
      expect((await db.select(db.categories).get()).single.name, 'Food');
      expect(raw.select('PRAGMA user_version').single.values.single, 3);
    });

    test('migration v1 -> v3 keeps data and leaves new columns and tables empty', () async {
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
      await verifier.migrateAndValidate(db, 3);

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
      expect(await db.select(db.recurringPayments).get(), isEmpty);
      expect(await db.select(db.recurringDues).get(), isEmpty);

      final fk = await db.customSelect('PRAGMA foreign_key_check').get();
      expect(fk, isEmpty);
    });

    test('migration v2 -> v3 keeps all data and adds empty tables', () async {
      final schema = await verifier.schemaAt(2);
      schema.rawDatabase
        ..execute(
          'INSERT INTO categories (id, kind, name, icon_key, sort_order, '
          "created_at, updated_at) VALUES ('c1', 'expense', 'Food', 'food', "
          '0, 1, 1)',
        )
        ..execute(
          'INSERT INTO accounts (id, name, icon_key, currency, '
          'currency_digits, opening_balance_minor, sort_order, archived_at, '
          'created_at, updated_at) VALUES '
          "('a1', 'Card', 'card', 'RUB', 2, 1000, 0, NULL, 1, 1), "
          "('a2', 'Old', 'cash', 'USD', 2, -5, 1, 77, 1, 1)",
        )
        ..execute(
          'INSERT INTO transactions (id, type, amount_minor, currency, '
          'occurred_on, occurred_at, category_id, note, created_at, '
          "updated_at, account_id) VALUES ('t1', 'expense', 12345, 'RUB', "
          "20261001, 111, 'c1', 'lunch', 5, 6, 'a1')",
        )
        ..execute(
          'INSERT INTO transfers (id, from_account_id, to_account_id, '
          'amount_minor, currency, occurred_on, occurred_at, created_at, '
          "updated_at) VALUES ('x1', 'a1', 'a2', 300, 'RUB', 20261002, 9, "
          '1, 1)',
        );

      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 3);

      final tx = await db.select(db.transactions).getSingle();
      expect(tx.id, 't1');
      expect(tx.amountMinor, 12345);
      expect(tx.accountId, 'a1');
      expect(tx.note, 'lunch');
      final accounts = await db.select(db.accounts).get();
      expect(accounts.map((a) => a.id), unorderedEquals(['a1', 'a2']));
      expect(accounts.singleWhere((a) => a.id == 'a2').archivedAt, 77);
      expect((await db.select(db.transfers).getSingle()).amountMinor, 300);
      expect((await db.select(db.categories).getSingle()).name, 'Food');
      expect(await db.select(db.recurringPayments).get(), isEmpty);
      expect(await db.select(db.recurringDues).get(), isEmpty);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    });

    test('an interrupted v2 -> v3 migration rolls back and retries', () async {
      final schema = await verifier.schemaAt(2);
      final raw = schema.rawDatabase
        ..execute(
          'INSERT INTO categories (id, kind, name, icon_key, sort_order, '
          "created_at, updated_at) VALUES ('c1', 'expense', 'Food', 'food', "
          '0, 1, 1)',
        )
        // Индекс с именем из миграции: она упадёт на нём уже после создания
        // таблиц.
        ..execute(
          'CREATE INDEX recurring_dues_transaction ON transactions (id)',
        );

      final broken = AppDatabase(schema.newConnection());
      await expectLater(
        broken.select(broken.categories).get(),
        throwsA(anything),
      );
      await broken.close();

      expect(raw.select('PRAGMA user_version').single.values.single, 2);
      final tables = raw
          .select("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((r) => r['name'] as String);
      expect(tables, isNot(contains('recurring_payments')));
      expect(tables, isNot(contains('recurring_dues')));

      raw.execute('DROP INDEX recurring_dues_transaction');
      final db = AppDatabase(schema.newConnection());
      addTearDown(db.close);
      await verifier.migrateAndValidate(db, 3);
      expect((await db.select(db.categories).get()).single.name, 'Food');
      expect(raw.select('PRAGMA user_version').single.values.single, 3);
    });

    group('recurring tables', () {
      late AppDatabase db;

      setUp(() async {
        db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        await db.customStatement(
          'INSERT INTO categories (id, kind, name, icon_key, sort_order, '
          "created_at, updated_at) VALUES ('c1', 'expense', 'Food', 'food', "
          '0, 1, 1)',
        );
      });

      Future<void> payment({
        String id = 'p1',
        String title = "'Internet'",
        String type = "'expense'",
        int amount = 65000,
        String currency = "'RUB'",
        String category = "'c1'",
        String unit = "'month'",
        int every = 1,
        int startsOn = 20261105,
        String endsOn = 'NULL',
        int remind = 1,
        String tracked = 'NULL',
      }) => db.customStatement(
        'INSERT INTO recurring_payments (id, title, type, amount_minor, '
        'currency, category_id, unit, every, starts_on, ends_on, remind, '
        'tracked_through, created_at, updated_at) VALUES '
        "('$id', $title, $type, $amount, $currency, $category, $unit, $every, "
        '$startsOn, $endsOn, $remind, $tracked, 1, 1)',
      );

      test('payments CHECK rejects bad rows and accepts good ones', () async {
        await payment();
        await db.customStatement('DELETE FROM recurring_payments');
        await payment(unit: "'week'", every: 99, endsOn: '20261105');
        await db.customStatement('DELETE FROM recurring_payments');
        await payment(tracked: '20261104', remind: 0);
        await db.customStatement('DELETE FROM recurring_payments');

        final bad = <String, Future<void> Function()>{
          'empty title': () => payment(title: "''"),
          'long title': () => payment(title: "'${'N' * 41}'"),
          'bad type': () => payment(type: "'transfer'"),
          'zero amount': () => payment(amount: 0),
          'negative amount': () => payment(amount: -1),
          'lowercase currency': () => payment(currency: "'rub'"),
          'long currency': () => payment(currency: "'USDT'"),
          'bad unit': () => payment(unit: "'day'"),
          'every 0': () => payment(every: 0),
          'every 100': () => payment(every: 100),
          'start out of range': () => payment(startsOn: 100),
          'end before start': () => payment(endsOn: '20261104'),
          'tracked out of range': () => payment(tracked: '5'),
          'remind 2': () => payment(remind: 2),
          'missing category': () => payment(category: "'nope'"),
        };
        for (final entry in bad.entries) {
          await expectLater(
            entry.value(),
            throwsA(anything),
            reason: entry.key,
          );
        }
      });

      test('dues CHECK, unique index and foreign keys', () async {
        await payment();
        await db.customStatement(
          'INSERT INTO transactions (id, type, amount_minor, currency, '
          'occurred_on, occurred_at, category_id, created_at, updated_at) '
          "VALUES ('t1', 'expense', 1, 'RUB', 20261105, 1, 'c1', 1, 1)",
        );
        Future<void> due({
          String id = 'd1',
          String payment = "'p1'",
          int dueOn = 20261105,
          String status = "'pending'",
          String tx = 'NULL',
        }) => db.customStatement(
          'INSERT INTO recurring_dues (id, payment_id, due_on, status, '
          'transaction_id, created_at, updated_at) VALUES '
          "('$id', $payment, $dueOn, $status, $tx, 1, 1)",
        );

        await due();
        await due(id: 'd2', dueOn: 20261205, status: "'skipped'");
        await due(id: 'd3', dueOn: 20270105, status: "'paid'", tx: "'t1'");

        // Дубль (payment_id, due_on) запрещён уникальным индексом.
        await expectLater(due(id: 'd4'), throwsA(anything));
        // paid без операции и операция у неоплаченной - нельзя.
        await expectLater(
          due(id: 'd5', dueOn: 20270205, status: "'paid'"),
          throwsA(anything),
        );
        await expectLater(
          due(id: 'd6', dueOn: 20270305, tx: "'t1'"),
          throwsA(anything),
        );
        await expectLater(
          due(id: 'd7', dueOn: 20270405, status: "'done'"),
          throwsA(anything),
        );
        await expectLater(due(id: 'd8', dueOn: 5), throwsA(anything));
        await expectLater(
          due(id: 'd9', dueOn: 20270505, payment: "'nope'"),
          throwsA(anything),
        );
        await expectLater(
          due(id: 'd10', dueOn: 20270605, status: "'paid'", tx: "'nope'"),
          throwsA(anything),
        );
      });
    });
  });
}
