import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/drift_data_eraser.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/features/accounts/data/accounts_repository_impl.dart';
import 'package:money_app/features/categories/data/default_categories_seeder.dart';
import 'package:money_app/features/categories/domain/default_categories.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';

import '../support/fake_id_generator.dart';
import '../support/fixed_clock.dart';

/// Генератор, который бросает ошибку на вызове номер [failAt].
final class _FailingIdGenerator implements IdGenerator {
  _FailingIdGenerator({required this.failAt});

  final int failAt;
  int _calls = 0;

  @override
  String newId() {
    _calls++;
    if (_calls == failAt) throw StateError('id generator failed');
    return 'new-$_calls';
  }
}

void main() {
  group('DriftDataEraser', () {
    late AppDatabase db;
    late FixedClock clock;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      clock = FixedClock(DateTime.utc(2026, 10, 10, 12));
      await DefaultCategoriesSeeder(
        db,
        idGenerator: FakeIdGenerator(prefix: 'old'),
        clock: clock,
      ).seed();
      await _fillEverything(db);
    });

    tearDown(() async {
      await db.close();
    });

    DriftDataEraser eraser([IdGenerator? ids]) => DriftDataEraser(
      db,
      idGenerator: ids ?? FakeIdGenerator(prefix: 'new'),
      clock: clock,
    );

    Future<int> count(String table) async {
      final row = await db
          .customSelect('SELECT COUNT(*) AS c FROM $table')
          .getSingle();
      return row.read<int>('c');
    }

    Future<List<List<Object?>>> settingsRows() async {
      final rows = await db
          .customSelect(
            'SELECT key, value, updated_at FROM app_settings ORDER BY key',
          )
          .get();
      return [
        for (final r in rows)
          [
            r.read<String>('key'),
            r.read<String>('value'),
            r.read<int>('updated_at'),
          ],
      ];
    }

    Future<void> expectStandardCategories() async {
      final rows = await db
          .customSelect(
            'SELECT kind, name, icon_key, parent_id, sort_order, '
            'archived_at, deleted_at FROM categories '
            'ORDER BY kind, sort_order',
          )
          .get();
      final actual = [
        for (final r in rows) [r.read<String>('kind'), r.read<String>('name')],
      ];
      final nextOrder = <String, int>{};
      final expected = <List<Object?>>[];
      for (final t in defaultCategories) {
        final order = nextOrder[t.kind.name] ?? 0;
        nextOrder[t.kind.name] = order + 1;
        expected.add([t.kind.name, t.name, t.iconKey, null, order, null, null]);
      }
      expected.sort((a, b) {
        final byKind = (a[0]! as String).compareTo(b[0]! as String);
        return byKind != 0 ? byKind : (a[4]! as int).compareTo(b[4]! as int);
      });
      expect(actual.length, defaultCategories.length);
      expect([
        for (final r in rows)
          [
            r.read<String>('kind'),
            r.read<String>('name'),
            r.read<String>('icon_key'),
            r.readNullable<String>('parent_id'),
            r.read<int>('sort_order'),
            r.readNullable<int>('archived_at'),
            r.readNullable<int>('deleted_at'),
          ],
      ], expected);
    }

    test('wipes data and leaves exactly the standard categories', () async {
      expect(await count('transactions'), 2);
      expect(await count('transfers'), 1);
      expect(await count('accounts'), 3);

      await eraser().eraseAll();

      expect(await count('transactions'), 0);
      expect(await count('transfers'), 0);
      expect(await count('accounts'), 0);
      await expectStandardCategories();
    });

    test('keeps app_settings rows untouched', () async {
      final before = await settingsRows();
      expect(before, isNotEmpty);

      await eraser().eraseAll();

      expect(await settingsRows(), before);
    });

    test('rolls back everything when seeding fails', () async {
      final categoriesBefore = await db
          .customSelect('SELECT id FROM categories ORDER BY id')
          .get();

      await expectLater(
        eraser(_FailingIdGenerator(failAt: 3)).eraseAll(),
        throwsA(isA<StateError>()),
      );

      expect(await count('transactions'), 2);
      expect(await count('transfers'), 1);
      expect(await count('accounts'), 3);
      final categoriesAfter = await db
          .customSelect('SELECT id FROM categories ORDER BY id')
          .get();
      expect(
        [for (final r in categoriesAfter) r.read<String>('id')],
        [for (final r in categoriesBefore) r.read<String>('id')],
      );
      expect((await settingsRows()), isNotEmpty);
    });

    test(
      'second eraseAll in a row gives the standard set without duplicates',
      () async {
        await eraser().eraseAll();
        await DriftDataEraser(
          db,
          idGenerator: FakeIdGenerator(prefix: 'again'),
          clock: clock,
        ).eraseAll();

        await expectStandardCategories();
      },
    );

    test(
      'guard: every table except app_settings and categories is empty',
      () async {
        await eraser().eraseAll();

        for (final table in db.allTables) {
          final name = table.actualTableName;
          if (name == 'app_settings' || name == 'categories') continue;
          expect(await count(name), 0, reason: 'table $name must be empty');
        }
      },
    );

    test('watchAll of accounts and transactions emit empty lists', () async {
      await eraser().eraseAll();

      final accounts = DriftAccountsRepository(db, clock: clock);
      final transactions = DriftTransactionsRepository(db, clock: clock);
      expect(await accounts.watchAll().first, isEmpty);
      expect(await transactions.watchAll().first, isEmpty);
    });
  });
}

/// Заполняет все таблицы: подкатегория, архивная категория, обычная и мягко
/// удалённая операции, три счёта (один архивный), перевод, настройки.
Future<void> _fillEverything(AppDatabase db) async {
  const t = 1760000000000;
  Future<void> run(String sql) => db.customStatement(sql);

  await run(
    'INSERT INTO categories (id, kind, name, icon_key, parent_id, sort_order, '
    'archived_at, created_at, updated_at, deleted_at) VALUES '
    "('sub-1', 'expense', 'Sub', 'x', 'old-1', 0, NULL, $t, $t, NULL), "
    "('arch-1', 'expense', 'Archived', 'x', NULL, 99, $t, $t, $t, NULL)",
  );
  await run(
    'INSERT INTO accounts (id, name, icon_key, currency, currency_digits, '
    'opening_balance_minor, sort_order, archived_at, created_at, updated_at, '
    'deleted_at) VALUES '
    "('acc-1', 'Card', 'card', 'RUB', 2, 1000, 0, NULL, $t, $t, NULL), "
    "('acc-2', 'Cash', 'cash', 'RUB', 2, 0, 1, NULL, $t, $t, NULL), "
    "('acc-3', 'Old', 'cash', 'RUB', 2, 0, 2, $t, $t, $t, NULL)",
  );
  await run(
    'INSERT INTO transactions (id, type, amount_minor, currency, occurred_on, '
    'occurred_at, category_id, subcategory_id, note, created_at, updated_at, '
    'deleted_at, account_id) VALUES '
    "('tx-1', 'expense', 500, 'RUB', 20261010, $t, 'old-1', 'sub-1', NULL, "
    "$t, $t, NULL, 'acc-1'), "
    "('tx-2', 'expense', 700, 'RUB', 20261009, $t, 'arch-1', NULL, NULL, "
    '$t, $t, $t, NULL)',
  );
  await run(
    'INSERT INTO transfers (id, from_account_id, to_account_id, amount_minor, '
    'currency, occurred_on, occurred_at, note, created_at, updated_at, '
    'deleted_at) VALUES '
    "('tr-1', 'acc-1', 'acc-2', 300, 'RUB', 20261010, $t, NULL, $t, $t, NULL)",
  );
  await run(
    'INSERT INTO app_settings (key, value, updated_at) VALUES '
    "('theme', 'dark', $t), ('default_currency', 'USD', $t), "
    "('default_account_id', 'acc-1', $t), ('last_export_at', '$t', $t)",
  );
}
