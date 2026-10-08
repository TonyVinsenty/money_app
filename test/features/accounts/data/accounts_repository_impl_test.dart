import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/errors/data_corrupted_exception.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/features/accounts/data/account_mapper.dart';
import 'package:money_app/features/accounts/data/accounts_repository_impl.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/account_rules.dart';

import '../../../support/fixed_clock.dart';

void main() {
  group('DriftAccountsRepository', () {
    late AppDatabase db;
    late FixedClock clock;
    late DriftAccountsRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      clock = FixedClock(DateTime.utc(2026, 10, 8, 12));
      repo = DriftAccountsRepository(db, clock: clock);
    });

    tearDown(() async {
      await db.close();
    });

    Account account(
      String id, {
      String? name,
      int sortOrder = 0,
      int minor = 0,
      DateTime? archivedAt,
    }) {
      return Account(
        id: id,
        name: name ?? 'Name $id',
        iconKey: 'card',
        openingBalance: Money.fromMinor(minor, 'RUB'),
        sortOrder: sortOrder,
        currencyDigits: 2,
        archivedAt: archivedAt,
      );
    }

    Future<AccountRow> raw(String id) {
      return (db.select(
        db.accounts,
      )..where((a) => a.id.equals(id))).getSingle();
    }

    Future<List<String>> ids() async {
      final list = await repo.watchAll().first;
      return list.map((a) => a.id).toList();
    }

    Future<List<int>> orders() async {
      final list = await repo.watchAll().first;
      return list.map((a) => a.sortOrder).toList();
    }

    Matcher rule(AccountRule r) =>
        throwsA(isA<AccountRuleException>().having((e) => e.rule, 'rule', r));

    test(
      'create and read back, including a negative opening balance',
      () async {
        await repo.create(account('a', minor: -50000));
        final found = await repo.findById('a');
        expect(found, account('a', minor: -50000));
        expect(found!.openingBalance.minorUnits, -50000);
        expect(await repo.findById('missing'), isNull);
        final row = await raw('a');
        expect(row.createdAt, clock.now().millisecondsSinceEpoch);
        expect(row.updatedAt, row.createdAt);
      },
    );

    test('an account with 4 decimals is saved, read back and kept by '
        'update', () async {
      final custom = Account(
        id: 'c',
        name: 'Custom',
        iconKey: 'card',
        openingBalance: Money.fromMinor(123456, 'ABC'),
        sortOrder: 0,
        currencyDigits: 4,
      );
      await repo.create(custom);
      expect((await raw('c')).currencyDigits, 4);
      expect(await repo.findById('c'), custom);
      expect((await repo.findById('c'))!.currencyDigits, 4);

      await repo.update('c', name: 'Renamed', iconKey: 'wallet');
      expect((await raw('c')).currencyDigits, 4);
      expect((await repo.findById('c'))!.currencyDigits, 4);
    });

    test('a USDT account with 8 decimals is saved', () async {
      await repo.create(
        Account(
          id: 'u',
          name: 'Tether',
          iconKey: 'card',
          openingBalance: Money.fromMinor(1, 'USDT'),
          sortOrder: 0,
          currencyDigits: 8,
        ),
      );
      final row = await raw('u');
      expect(row.currency, 'USDT');
      expect(row.currencyDigits, 8);
    });

    test(
      'create checks currency digits against catalog and accounts',
      () async {
        Account withCurrency(String id, String name, String code, int digits) =>
            Account(
              id: id,
              name: name,
              iconKey: 'card',
              openingBalance: Money.zero(code),
              sortOrder: 0,
              currencyDigits: digits,
            );
        await expectLater(
          repo.create(withCurrency('u', 'Usd', 'USD', 4)),
          rule(AccountRule.currencyDigitsMismatch),
        );
        await repo.create(withCurrency('a', 'One', 'ABC', 4));
        await repo.archive('a');
        // Архивный счёт тоже задаёт знаки своего кода.
        await expectLater(
          repo.create(withCurrency('b', 'Two', 'ABC', 3)),
          rule(AccountRule.currencyDigitsMismatch),
        );
        await repo.create(withCurrency('c', 'Three', 'ABC', 4));
        expect(await ids(), ['a', 'c']);
      },
    );

    test('create rejects a duplicate name among live accounts', () async {
      await repo.create(account('a', name: 'Card'));
      await expectLater(
        repo.create(account('b', name: '  card ')),
        rule(AccountRule.duplicateName),
      );
      expect(await ids(), ['a']);
    });

    test('an archived name does not block create', () async {
      await repo.create(account('a', name: 'Card'));
      await repo.archive('a');
      await repo.create(account('b', name: 'Card'));
      expect(await ids(), ['a', 'b']);
    });

    test(
      'nextSortOrder counts archived and ignores corrupted neighbours',
      () async {
        expect(await repo.nextSortOrder(), 0);
        await repo.create(account('a', sortOrder: 0));
        await repo.create(account('b', sortOrder: 4));
        await repo.archive('b');
        expect(await repo.nextSortOrder(), 5);
      },
    );

    test(
      'watchAll is ordered, includes archived and emits after writes',
      () async {
        final emitted = <List<String>>[];
        final sub = repo.watchAll().listen(
          (l) => emitted.add(l.map((a) => a.id).toList()),
        );
        await repo.create(account('b', sortOrder: 1));
        await repo.create(account('a', sortOrder: 0));
        await repo.archive('a');
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await sub.cancel();
        expect(emitted.last, ['a', 'b']);
        expect(emitted.length, greaterThan(1));
      },
    );

    test('update changes name and icon and bumps updated_at', () async {
      await repo.create(account('a', name: 'Card'));
      clock.advance(const Duration(hours: 1));
      await repo.update('a', name: ' Cash ', iconKey: 'wallet');
      final found = (await repo.findById('a'))!;
      expect(found.name, 'Cash');
      expect(found.iconKey, 'wallet');
      expect((await raw('a')).updatedAt, clock.now().millisecondsSinceEpoch);
    });

    test('update validates name, icon and duplicates', () async {
      await repo.create(account('a', name: 'Card'));
      await repo.create(account('b', name: 'Cash', sortOrder: 1));
      await expectLater(
        repo.update('b', name: 'CARD', iconKey: 'x'),
        rule(AccountRule.duplicateName),
      );
      await expectLater(
        repo.update('b', name: ' ', iconKey: 'x'),
        rule(AccountRule.emptyName),
      );
      await expectLater(
        repo.update('b', name: 'Cash', iconKey: ' '),
        rule(AccountRule.emptyIconKey),
      );
      // Своё же имя (в другом регистре) дублем не считается.
      await repo.update('b', name: 'CASH', iconKey: 'x');
      await expectLater(
        repo.update('missing', name: 'n', iconKey: 'x'),
        throwsArgumentError,
      );
    });

    test(
      'setOpeningBalance stores a signed amount and bumps updated_at',
      () async {
        await repo.create(account('a', minor: 100));
        clock.advance(const Duration(minutes: 5));
        await repo.setOpeningBalance('a', Money.fromMinor(-2500, 'RUB'));
        expect((await repo.findById('a'))!.openingBalance.minorUnits, -2500);
        expect((await raw('a')).updatedAt, clock.now().millisecondsSinceEpoch);
        await expectLater(
          repo.setOpeningBalance('missing', Money.zero('RUB')),
          throwsArgumentError,
        );
        await expectLater(
          repo.setOpeningBalance('a', Money.fromMinor(100, 'EUR')),
          throwsArgumentError,
        );
        expect((await repo.findById('a'))!.openingBalance.currency, 'RUB');
      },
    );

    test('reorder puts requested first, others follow, no gaps', () async {
      await repo.create(account('a', sortOrder: 0));
      await repo.create(account('b', sortOrder: 1));
      await repo.create(account('c', sortOrder: 2));
      await repo.create(account('d', sortOrder: 3));
      await repo.archive('b');
      await repo.reorder(['d', 'c']);
      expect(await ids(), ['d', 'c', 'a', 'b']);
      expect(await orders(), [0, 1, 2, 3]);
    });

    test(
      'reorder repairs duplicate numbers and skips unchanged rows',
      () async {
        await repo.create(account('a', sortOrder: 0));
        await repo.create(account('b', sortOrder: 0));
        clock.advance(const Duration(hours: 1));
        await repo.reorder(['a', 'b']);
        expect(await orders(), [0, 1]);
        expect(
          (await raw('a')).updatedAt,
          isNot(clock.now().millisecondsSinceEpoch),
        );
        expect((await raw('b')).updatedAt, clock.now().millisecondsSinceEpoch);
      },
    );

    test(
      'reorder rejects duplicates and unknown ids, writes nothing',
      () async {
        await repo.create(account('a', sortOrder: 0));
        await repo.create(account('b', sortOrder: 1));
        await expectLater(repo.reorder(['a', 'a']), throwsArgumentError);
        await expectLater(repo.reorder(['b', 'zzz']), throwsArgumentError);
        await repo.reorder([]);
        expect(await ids(), ['a', 'b']);
      },
    );

    test('archive and restore change archived_at and updated_at', () async {
      await repo.create(account('a'));
      clock.advance(const Duration(hours: 1));
      await repo.archive('a');
      var row = await raw('a');
      expect(row.archivedAt, clock.now().millisecondsSinceEpoch);
      expect(row.updatedAt, clock.now().millisecondsSinceEpoch);
      expect((await repo.findById('a'))!.isArchived, isTrue);

      // Повторная архивация ничего не меняет.
      clock.advance(const Duration(hours: 1));
      await repo.archive('a');
      expect(
        (await raw('a')).archivedAt,
        isNot(clock.now().millisecondsSinceEpoch),
      );

      await repo.restore('a');
      row = await raw('a');
      expect(row.archivedAt, isNull);
      expect(row.updatedAt, clock.now().millisecondsSinceEpoch);
      await expectLater(repo.archive('missing'), throwsArgumentError);
    });

    test('restore fails when the name was taken meanwhile', () async {
      await repo.create(account('a', name: 'Card'));
      await repo.archive('a');
      await repo.create(account('b', name: 'card', sortOrder: 1));
      await expectLater(repo.restore('a'), rule(AccountRule.duplicateName));
      expect((await raw('a')).archivedAt, isNotNull);
    });

    test('a corrupted row is DataCorruptedException', () async {
      await db.customStatement(
        'INSERT INTO accounts (id, name, icon_key, currency, currency_digits, '
        'opening_balance_minor, sort_order, created_at, updated_at) '
        "VALUES ('bad', 'Bad', 'card', 'RUB', 2, 0, -1, 1, 1)",
      );
      await expectLater(
        repo.findById('bad'),
        throwsA(isA<DataCorruptedException>()),
      );
      await expectLater(
        repo.watchAll().first,
        throwsA(isA<DataCorruptedException>()),
      );
      // Испорченный сосед не мешает добавить новый счёт.
      expect(await repo.nextSortOrder(), 0);
      await repo.create(account('ok', name: 'Ok'));
    });
  });

  group('account mapper', () {
    AccountRow row({int? archivedAt, String iconKey = 'card'}) => AccountRow(
      id: 'r',
      name: 'Card',
      iconKey: iconKey,
      currency: 'RUB',
      currencyDigits: 2,
      openingBalanceMinor: -1234,
      sortOrder: 2,
      archivedAt: archivedAt,
      createdAt: 1,
      updatedAt: 1,
    );

    test('maps every field, archivedAt becomes UTC', () {
      final a = accountFromRow(row(archivedAt: 1700000000000));
      expect(a.openingBalance, Money.fromMinor(-1234, 'RUB'));
      expect(a.sortOrder, 2);
      expect(a.currencyDigits, 2);
      expect(a.archivedAt, DateTime.utc(2023, 11, 14, 22, 13, 20));
      expect(a.archivedAt!.isUtc, isTrue);
    });

    test('a broken row is DataCorruptedException with the row id', () {
      expect(
        () => accountFromRow(row(iconKey: ' ')),
        throwsA(
          isA<DataCorruptedException>()
              .having((e) => e.message, 'message', contains('"r"'))
              .having((e) => e.cause, 'cause', isA<AccountRuleException>()),
        ),
      );
    });

    test('accountToCompanion writes integers', () {
      final c = accountToCompanion(
        Account(
          id: 'a',
          name: 'Card',
          iconKey: 'card',
          openingBalance: Money.fromMinor(-5, 'EUR'),
          sortOrder: 1,
          currencyDigits: 2,
          archivedAt: DateTime.utc(2026, 1, 1),
        ),
        createdAt: DateTime.utc(2026, 1, 2),
        updatedAt: DateTime.utc(2026, 1, 3),
      );
      expect(c.currency.value, 'EUR');
      expect(c.openingBalanceMinor.value, -5);
      expect(
        c.archivedAt.value,
        DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
      );
      expect(
        c.updatedAt.value,
        DateTime.utc(2026, 1, 3).millisecondsSinceEpoch,
      );
    });
  });
}
