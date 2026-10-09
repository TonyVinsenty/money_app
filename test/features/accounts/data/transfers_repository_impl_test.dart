import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/accounts/data/accounts_repository_impl.dart';
import 'package:money_app/features/accounts/data/transfers_repository_impl.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/transfer.dart';
import 'package:money_app/features/accounts/domain/transfer_rules.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/fixed_clock.dart';
import '../../../support/in_memory_database.dart';

void main() {
  late AppDatabase db;
  late FixedClock clock;
  late DriftAccountsRepository accounts;
  late DriftTransfersRepository transfers;
  late DriftTransactionsRepository transactions;

  Future<void> addAccount(
    String id, {
    int opening = 0,
    String currency = 'RUB',
    DateTime? archivedAt,
  }) {
    return accounts.create(
      Account(
        id: id,
        name: 'Account $id',
        iconKey: 'card',
        openingBalance: Money.fromMinor(opening, currency),
        sortOrder: 0,
        currencyDigits: 2,
        archivedAt: archivedAt,
      ),
    );
  }

  setUp(() async {
    db = await openInMemoryDatabase();
    clock = FixedClock(DateTime.utc(2026, 10, 9, 12));
    accounts = DriftAccountsRepository(db, clock: clock);
    transfers = DriftTransfersRepository(db, clock: clock);
    transactions = DriftTransactionsRepository(db, clock: clock);
    await db.customStatement(
      'INSERT INTO categories (id, kind, name, icon_key, parent_id, '
      'sort_order, created_at, updated_at) '
      "VALUES ('cat-e', 'expense', 'E', 'i', NULL, 0, 1, 1)",
    );
    await addAccount('a', opening: 1000);
    await addAccount('b', opening: 500);
    await addAccount('c');
  });

  tearDown(() => db.close());

  Transfer tr(
    String id, {
    String from = 'a',
    String to = 'b',
    int minor = 300,
    String currency = 'RUB',
    int day = 1,
    int hour = 9,
    String? note,
  }) {
    return Transfer(
      id: id,
      fromAccountId: from,
      toAccountId: to,
      amount: Money.fromMinor(minor, currency),
      occurredOn: DateOnly(2026, 10, day),
      occurredAt: DateTime.utc(2026, 10, day, hour),
      note: note,
    );
  }

  Future<Map<String, int>> balances() async {
    final map = await accounts.watchBalances().first;
    return {for (final e in map.entries) e.key: e.value.minorUnits};
  }

  Future<List<String>> idsFor(String accountId) async {
    final list = await transfers.watchForAccount(accountId).first;
    return [for (final t in list) t.id];
  }

  test('add changes both balances', () async {
    await transfers.add(tr('t1'));
    expect(await balances(), {'a': 700, 'b': 800, 'c': 0});
  });

  test('update changes amount and accounts', () async {
    await transfers.add(tr('t1'));
    await transfers.update(tr('t1', from: 'b', to: 'c', minor: 100));
    expect(await balances(), {'a': 1000, 'b': 400, 'c': 100});
    expect(await idsFor('a'), isEmpty);
    expect(await idsFor('c'), ['t1']);
  });

  test('softDelete and restore return the balances', () async {
    await transfers.add(tr('t1'));
    await transfers.softDelete('t1');
    expect(await balances(), {'a': 1000, 'b': 500, 'c': 0});
    expect(await idsFor('a'), isEmpty);
    await transfers.softDelete('t1'); // Повтор - без ошибки.
    await transfers.restore('t1');
    expect(await balances(), {'a': 700, 'b': 800, 'c': 0});
    expect(await idsFor('a'), ['t1']);
    await transfers.restore('t1'); // Повтор - без ошибки.
  });

  test('update of a deleted transfer and unknown ids fail', () async {
    await transfers.add(tr('t1'));
    await transfers.softDelete('t1');
    expect(() => transfers.update(tr('t1')), throwsArgumentError);
    expect(() => transfers.update(tr('nope')), throwsArgumentError);
    expect(() => transfers.softDelete('nope'), throwsArgumentError);
    expect(() => transfers.restore('nope'), throwsArgumentError);
  });

  test('new transfer with an archived account is rejected', () async {
    await addAccount('old', archivedAt: DateTime.utc(2026, 1, 1));
    for (final t in [tr('x', from: 'old'), tr('y', to: 'old')]) {
      expect(
        () => transfers.add(t),
        throwsA(
          isA<TransferRuleException>().having(
            (e) => e.rule,
            'rule',
            TransferRule.accountArchived,
          ),
        ),
      );
    }
    expect(await idsFor('old'), isEmpty);
  });

  test('editing note of a transfer with an archived account is fine', () async {
    await transfers.add(tr('t1'));
    await accounts.archive('a');
    await transfers.update(tr('t1', minor: 450, day: 2, note: 'rent'));
    final saved = (await transfers.watchForAccount('a').first).single;
    expect(saved.note, 'rent');
    expect(saved.amount.minorUnits, 450);
    // А смена на архивный счёт - нет.
    await accounts.archive('c');
    expect(
      () => transfers.update(tr('t1', from: 'a', to: 'c')),
      throwsA(isA<TransferRuleException>()),
    );
  });

  test('currency mismatch is rejected', () async {
    await addAccount('usd', currency: 'USD');
    await addAccount('usd2', currency: 'USD');
    for (final t in [
      tr('x', to: 'usd', currency: 'RUB'),
      tr('y', from: 'usd', to: 'usd2', currency: 'RUB'),
      tr('z', currency: 'USD'),
    ]) {
      expect(
        () => transfers.add(t),
        throwsA(
          isA<TransferRuleException>().having(
            (e) => e.rule,
            'rule',
            TransferRule.currencyMismatch,
          ),
        ),
      );
    }
    await transfers.add(tr('ok', from: 'usd', to: 'usd2', currency: 'USD'));
    // Правка тоже проверяет валюту.
    expect(
      () => transfers.update(tr('ok', from: 'usd', to: 'usd2')),
      throwsA(isA<TransferRuleException>()),
    );
  });

  test('missing or deleted account is an ArgumentError', () async {
    expect(() => transfers.add(tr('x', to: 'ghost')), throwsArgumentError);
    expect(() => transfers.add(tr('y', from: 'ghost')), throwsArgumentError);
    await db.customStatement(
      "UPDATE accounts SET deleted_at = 5 WHERE id = 'c'",
    );
    expect(() => transfers.add(tr('z', to: 'c')), throwsArgumentError);
  });

  test('month totals of operations ignore transfers', () async {
    await transfers.add(tr('t1', minor: 900));
    await transactions.add(
      Transaction(
        id: 'e1',
        type: TransactionType.expense,
        amount: Money.fromMinor(40, 'RUB'),
        occurredOn: DateOnly(2026, 10, 1),
        occurredAt: DateTime.utc(2026, 10, 1, 9),
        categoryId: 'cat-e',
        accountId: 'a',
      ),
    );
    final period = DateRange(DateOnly(2026, 10, 1), DateOnly(2026, 10, 31));
    for (final type in TransactionType.values) {
      final total = await transactions
          .watchTotal(type: type, period: period)
          .first;
      expect(
        total.minorUnits,
        type == TransactionType.expense ? 40 : 0,
        reason: type.name,
      );
    }
  });

  test(
    'watchForAccount: both sides, newest first, other accounts out',
    () async {
      await transfers.add(tr('old', day: 1));
      await transfers.add(tr('morning', from: 'c', to: 'a', day: 5, hour: 8));
      await transfers.add(tr('evening', day: 5, hour: 20));
      await transfers.add(tr('other', from: 'b', to: 'c', day: 9));
      expect(await idsFor('a'), ['evening', 'morning', 'old']);
      expect(await idsFor('c'), ['other', 'morning']);
    },
  );

  test('watchForAccount emits again after a write', () async {
    final stream = transfers.watchForAccount('a');
    final expectation = expectLater(
      stream.map((l) => l.length),
      emitsInOrder([0, 1]),
    );
    await Future<void>.delayed(Duration.zero);
    await transfers.add(tr('t1'));
    await expectation;
  });
}
