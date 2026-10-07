import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

void main() {
  group('transactions table', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> insertCategory(String id, {String? parentId}) {
      return db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: id,
              kind: 'expense',
              name: 'Name $id',
              iconKey: 'icon_$id',
              sortOrder: 0,
              createdAt: 1000,
              updatedAt: 2000,
              parentId: Value(parentId),
            ),
          );
    }

    Future<void> insert(
      String id, {
      TransactionType type = TransactionType.expense,
      int amountMinor = 100,
      String currency = 'RUB',
      DateOnly? occurredOn,
      int occurredAt = 1700000000000,
      String categoryId = 'food',
      String? subcategoryId,
      String? note,
      int? deletedAt,
    }) {
      return db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              id: id,
              type: type,
              amountMinor: amountMinor,
              currency: currency,
              occurredOn: occurredOn ?? DateOnly(2026, 9, 19),
              occurredAt: occurredAt,
              categoryId: categoryId,
              createdAt: 1000,
              updatedAt: 2000,
              subcategoryId: Value(subcategoryId),
              note: Value(note),
              deletedAt: Value(deletedAt),
            ),
          );
    }

    Matcher throwsSqlite(String text) => throwsA(
      isA<SqliteException>().having(
        (e) => e.message,
        'message',
        contains(text),
      ),
    );

    test('writes a transaction and reads all fields back', () async {
      await insertCategory('food');
      await insertCategory('bakery', parentId: 'food');

      await insert(
        't1',
        type: TransactionType.income,
        amountMinor: 123456,
        currency: 'USD',
        occurredOn: DateOnly(2026, 1, 5),
        occurredAt: 1767600000000,
        subcategoryId: 'bakery',
        note: 'Bread',
        deletedAt: 9000,
      );

      final row = await db.select(db.transactions).getSingle();

      expect(row.id, 't1');
      expect(row.type, TransactionType.income);
      expect(row.amountMinor, 123456);
      expect(row.currency, 'USD');
      expect(row.occurredOn, DateOnly(2026, 1, 5));
      expect(row.occurredAt, 1767600000000);
      expect(row.categoryId, 'food');
      expect(row.subcategoryId, 'bakery');
      expect(row.note, 'Bread');
      expect(row.createdAt, 1000);
      expect(row.updatedAt, 2000);
      expect(row.deletedAt, 9000);
    });

    test('nullable columns default to null', () async {
      await insertCategory('food');
      await insert('t1');

      final row = await db.select(db.transactions).getSingle();

      expect(row.subcategoryId, isNull);
      expect(row.note, isNull);
      expect(row.deletedAt, isNull);
    });

    test('database stores plain integers and text, not objects', () async {
      await insertCategory('food');
      await insert(
        't1',
        type: TransactionType.expense,
        amountMinor: 35000,
        occurredOn: DateOnly(2026, 9, 19),
        occurredAt: 1789800000000,
      );

      final raw = await db.customSelect('''
        SELECT occurred_on, type, amount_minor, occurred_at,
               typeof(occurred_on) AS on_type,
               typeof(type) AS type_type,
               typeof(amount_minor) AS amount_type,
               typeof(occurred_at) AS at_type
        FROM transactions
        ''').getSingle();

      expect(raw.read<int>('occurred_on'), 20260919);
      expect(raw.read<String>('type'), 'expense');
      expect(raw.read<int>('amount_minor'), 35000);
      expect(raw.read<int>('occurred_at'), 1789800000000);
      expect(raw.read<String>('on_type'), 'integer');
      expect(raw.read<String>('type_type'), 'text');
      expect(raw.read<String>('amount_type'), 'integer');
      expect(raw.read<String>('at_type'), 'integer');
    });

    test('reference to a missing category is rejected', () async {
      await expectLater(
        insert('t1', categoryId: 'no_such_category'),
        throwsSqlite('FOREIGN KEY constraint failed'),
      );

      expect(await db.select(db.transactions).get(), isEmpty);
    });

    test('reference to a missing subcategory is rejected', () async {
      await insertCategory('food');

      await expectLater(
        insert('t1', subcategoryId: 'no_such_subcategory'),
        throwsSqlite('FOREIGN KEY constraint failed'),
      );

      expect(await db.select(db.transactions).get(), isEmpty);
    });

    test('required columns are NOT NULL', () async {
      await insertCategory('food');

      // Каждый запрос пропускает ровно одну обязательную колонку.
      const all = {
        'id': "'x'",
        'type': "'expense'",
        'amount_minor': '100',
        'currency': "'RUB'",
        'occurred_on': '20260919',
        'occurred_at': '1',
        'category_id': "'food'",
        'created_at': '1',
        'updated_at': '1',
      };
      for (final skipped in all.keys) {
        final columns = all.keys.where((c) => c != skipped).toList();
        final values = columns.map((c) => all[c]).join(', ');
        await expectLater(
          db.customInsert(
            'INSERT INTO transactions (${columns.join(', ')}) '
            'VALUES ($values)',
          ),
          throwsSqlite('NOT NULL constraint failed'),
          reason: 'без колонки $skipped вставка должна падать',
        );
      }

      expect(await db.select(db.transactions).get(), isEmpty);
    });

    test(
      'amount_minor: negative is rejected, zero and one are accepted',
      () async {
        await insertCategory('food');

        await expectLater(
          insert('neg', amountMinor: -1),
          throwsSqlite('CHECK constraint failed'),
        );
        await insert('zero', amountMinor: 0);
        await insert('one', amountMinor: 1);

        final rows = await db.select(db.transactions).get();
        expect(rows.map((t) => t.id), unorderedEquals(['zero', 'one']));
      },
    );

    test('currency must be exactly three uppercase Latin letters', () async {
      await insertCategory('food');

      for (final bad in ['rub', 'Rub', 'РУБ', '123', 'RU', 'RUBL', '']) {
        await expectLater(
          insert('bad', currency: bad),
          throwsSqlite('CHECK constraint failed'),
          reason: 'валюта "$bad" должна отклоняться',
        );
      }
      await insert('rub', currency: 'RUB');
      await insert('usd', currency: 'USD');

      final rows = await db.select(db.transactions).get();
      expect(rows.map((t) => t.id), unorderedEquals(['rub', 'usd']));
    });

    test('occurred_on must be within 10101..99991231', () async {
      await insertCategory('food');

      // Пишем сырым SQL: DateOnly не даст создать значение вне диапазона.
      Future<void> insertRaw(String id, int occurredOn) => db.customInsert(
        'INSERT INTO transactions (id, type, amount_minor, currency, '
        'occurred_on, occurred_at, category_id, created_at, updated_at) '
        "VALUES ('$id', 'expense', 100, 'RUB', $occurredOn, 1, 'food', 1, 1)",
      );

      for (final bad in [0, -1, 10100, 99991232, 100000000]) {
        await expectLater(
          insertRaw('bad', bad),
          throwsSqlite('CHECK constraint failed'),
          reason: 'occurred_on = $bad должен отклоняться',
        );
      }
      await insertRaw('min', 10101);
      await insertRaw('max', 99991231);

      final raw = await db
          .customSelect('SELECT id FROM transactions ORDER BY id')
          .get();
      expect(raw.map((r) => r.read<String>('id')), ['max', 'min']);
    });

    test('note: 1 and 200 characters and NULL are accepted, '
        'empty and 201 are rejected', () async {
      await insertCategory('food');

      await insert('n1', note: 'a');
      await insert('n200', note: 'a' * 200);
      await insert('nnull', note: null);
      await expectLater(
        insert('n0', note: ''),
        throwsSqlite('CHECK constraint failed'),
      );
      await expectLater(
        insert('n201', note: 'a' * 201),
        throwsSqlite('CHECK constraint failed'),
      );

      final rows = await db.select(db.transactions).get();
      expect(rows.map((t) => t.id), unorderedEquals(['n1', 'n200', 'nnull']));
    });

    test('note length is counted in characters, not bytes', () async {
      await insertCategory('food');

      // 200 русских букв — это 400 байт в UTF-8, но 200 символов.
      await insert('ru200', note: 'ж' * 200);
      await expectLater(
        insert('ru201', note: 'ж' * 201),
        throwsSqlite('CHECK constraint failed'),
      );
    });

    test('type other than income or expense is rejected', () async {
      await insertCategory('food');

      await expectLater(
        db.customInsert(
          'INSERT INTO transactions (id, type, amount_minor, currency, '
          'occurred_on, occurred_at, category_id, created_at, updated_at) '
          "VALUES ('x', 'other', 100, 'RUB', 20260919, 1, 'food', 1, 1)",
        ),
        throwsSqlite('CHECK constraint failed'),
      );

      expect(await db.select(db.transactions).get(), isEmpty);
    });

    test('selects a period by occurred_on in the right order', () async {
      await insertCategory('food');
      await insert('before', occurredOn: DateOnly(2026, 8, 31));
      await insert(
        'sep2_late',
        occurredOn: DateOnly(2026, 9, 2),
        occurredAt: 2000,
      );
      await insert(
        'sep2_early',
        occurredOn: DateOnly(2026, 9, 2),
        occurredAt: 1000,
      );
      await insert('sep1', occurredOn: DateOnly(2026, 9, 1));
      await insert('sep30', occurredOn: DateOnly(2026, 9, 30));
      await insert('after', occurredOn: DateOnly(2026, 10, 1));

      final from = DateOnly(2026, 9, 1);
      final to = DateOnly(2026, 9, 30);
      final rows =
          await (db.select(db.transactions)
                ..where(
                  (t) => t.occurredOn.isBetweenValues(from.toInt(), to.toInt()),
                )
                ..orderBy([
                  (t) => OrderingTerm.asc(t.occurredOn),
                  (t) => OrderingTerm.asc(t.occurredAt),
                ]))
              .get();

      // Границы периода входят включительно.
      expect(rows.map((t) => t.id), [
        'sep1',
        'sep2_early',
        'sep2_late',
        'sep30',
      ]);
      expect(rows.first.occurredOn, from);
      expect(rows.last.occurredOn, to);
    });

    test('history order: newest day first, then latest moment first', () async {
      await insertCategory('food');
      await insert('sep1', occurredOn: DateOnly(2026, 9, 1), occurredAt: 9000);
      await insert(
        'sep2_early',
        occurredOn: DateOnly(2026, 9, 2),
        occurredAt: 1000,
      );
      await insert(
        'sep2_late',
        occurredOn: DateOnly(2026, 9, 2),
        occurredAt: 2000,
      );
      await insert('sep3', occurredOn: DateOnly(2026, 9, 3), occurredAt: 500);
      await insert(
        'sep2_deleted',
        occurredOn: DateOnly(2026, 9, 2),
        occurredAt: 3000,
        deletedAt: 5000,
      );

      final rows =
          await (db.select(db.transactions)
                ..where((t) => t.deletedAt.isNull())
                ..orderBy([
                  (t) => OrderingTerm.desc(t.occurredOn),
                  (t) => OrderingTerm.desc(t.occurredAt),
                ]))
              .get();

      expect(rows.map((t) => t.id), [
        'sep3',
        'sep2_late',
        'sep2_early',
        'sep1',
      ]);
    });

    test('soft-deleted row is stored and readable', () async {
      await insertCategory('food');
      await insert('live');
      await insert('gone', deletedAt: 5000);

      final rows = await db.select(db.transactions).get();

      expect(rows.map((t) => t.id), unorderedEquals(['live', 'gone']));
      expect(rows.singleWhere((t) => t.id == 'gone').deletedAt, 5000);
    });

    test('columns have expected types and nullability', () async {
      final rows = await db
          .customSelect('PRAGMA table_info(transactions)')
          .get();
      final byName = {for (final r in rows) r.read<String>('name'): r};

      String type(String c) => byName[c]!.read<String>('type');
      int notNull(String c) => byName[c]!.read<int>('notnull');

      expect(
        byName.keys,
        unorderedEquals([
          'id',
          'type',
          'amount_minor',
          'currency',
          'occurred_on',
          'occurred_at',
          'category_id',
          'subcategory_id',
          'note',
          'created_at',
          'updated_at',
          'deleted_at',
          'account_id',
        ]),
      );
      expect(byName['id']!.read<int>('pk'), 1);
      for (final c in [
        'id',
        'type',
        'currency',
        'category_id',
        'subcategory_id',
        'note',
        'account_id',
      ]) {
        expect(type(c), 'TEXT', reason: c);
      }
      for (final c in [
        'amount_minor',
        'occurred_on',
        'occurred_at',
        'created_at',
        'updated_at',
        'deleted_at',
      ]) {
        expect(type(c), 'INTEGER', reason: c);
      }
      const nullable = ['subcategory_id', 'note', 'deleted_at', 'account_id'];
      for (final c in nullable) {
        expect(notNull(c), 0, reason: c);
      }
      for (final c in byName.keys.where((c) => !nullable.contains(c))) {
        expect(notNull(c), 1, reason: c);
      }
    });

    test('foreign keys point to categories.id and accounts.id', () async {
      final rows = await db
          .customSelect('PRAGMA foreign_key_list(transactions)')
          .get();

      expect(rows, hasLength(3));
      final tableByColumn = {
        for (final r in rows) r.read<String>('from'): r.read<String>('table'),
      };
      expect(tableByColumn, {
        'category_id': 'categories',
        'subcategory_id': 'categories',
        'account_id': 'accounts',
      });
      for (final r in rows) {
        expect(r.read<String>('to'), 'id');
      }
    });

    test('exactly three partial indexes cover only live rows', () async {
      final list = await db
          .customSelect('PRAGMA index_list(transactions)')
          .get();
      // origin 'c' — индексы, созданные командой CREATE INDEX (не ключом).
      final created = {
        for (final r in list.where((r) => r.read<String>('origin') == 'c'))
          r.read<String>('name'): r.read<int>('partial'),
      };

      expect(created, {
        'transactions_occurred_on_at': 1,
        'transactions_category_occurred_on': 1,
        'transactions_account': 1,
      });

      final master = await db
          .customSelect(
            "SELECT name, sql FROM sqlite_master WHERE type = 'index' "
            "AND tbl_name = 'transactions' AND sql IS NOT NULL",
          )
          .get();
      final sqlByName = {
        for (final r in master) r.read<String>('name'): r.read<String>('sql'),
      };

      expect(
        sqlByName['transactions_occurred_on_at'],
        allOf(
          contains('(occurred_on, occurred_at)'),
          endsWith('deleted_at IS NULL'),
        ),
      );
      expect(
        sqlByName['transactions_category_occurred_on'],
        allOf(
          contains('(category_id, occurred_on)'),
          endsWith('deleted_at IS NULL'),
        ),
      );
    });
  });
}
