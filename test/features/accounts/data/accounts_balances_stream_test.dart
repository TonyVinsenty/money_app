import 'package:drift/drift.dart' show TableUpdate;
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/accounts/data/accounts_repository_impl.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/account_balances.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/fixed_clock.dart';
import '../../../support/in_memory_database.dart';

void main() {
  late AppDatabase db;
  late DriftAccountsRepository accounts;
  late DriftTransactionsRepository transactions;

  setUp(() async {
    db = await openInMemoryDatabase();
    final clock = FixedClock(DateTime.utc(2026, 10, 8, 12));
    accounts = DriftAccountsRepository(db, clock: clock);
    transactions = DriftTransactionsRepository(db, clock: clock);
    await db.customStatement(
      'INSERT INTO categories (id, kind, name, icon_key, parent_id, '
      'sort_order, created_at, updated_at) '
      "VALUES ('cat-e', 'expense', 'E', 'i', NULL, 0, 1, 1), "
      "('cat-i', 'income', 'I', 'i', NULL, 1, 1, 1)",
    );
  });

  tearDown(() => db.close());

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
        archivedAt: archivedAt,
      ),
    );
  }

  Transaction tx(
    String id,
    int minor, {
    TransactionType type = TransactionType.expense,
    String? accountId,
    String currency = 'RUB',
  }) {
    return Transaction(
      id: id,
      type: type,
      amount: Money.fromMinor(minor, currency),
      occurredOn: DateOnly(2026, 10, 1),
      occurredAt: DateTime.utc(2026, 10, 1, 9),
      categoryId: type == TransactionType.expense ? 'cat-e' : 'cat-i',
      accountId: accountId,
    );
  }

  Future<void> transfer(
    String id,
    String from,
    String to,
    int minor, {
    String currency = 'RUB',
    bool deleted = false,
  }) async {
    await db.customStatement(
      'INSERT INTO transfers (id, from_account_id, to_account_id, '
      'amount_minor, currency, occurred_on, occurred_at, created_at, '
      'updated_at, deleted_at) '
      "VALUES ('$id', '$from', '$to', $minor, '$currency', 20261001, 1, 1, "
      "1, ${deleted ? 5 : 'NULL'})",
    );
    // Сырой SQL drift не замечает: сообщаем об изменении вручную.
    db.notifyUpdates({TableUpdate.onTable(db.transfers)});
  }

  Future<Map<String, int>> balances([String currency = 'RUB']) async {
    final map = await accounts.watchBalances(currency: currency).first;
    return {for (final e in map.entries) e.key: e.value.minorUnits};
  }

  test('no movements: opening balances, archived included', () async {
    await addAccount('a', opening: 1000);
    await addAccount('b', opening: -50, archivedAt: DateTime.utc(2026, 1, 1));
    expect(await balances(), {'a': 1000, 'b': -50});
  });

  test('income and expense are split, other currency is ignored', () async {
    await addAccount('a', opening: 1000);
    await addAccount('usd', opening: 7, currency: 'USD');
    await transactions.add(tx('t1', 300, accountId: 'a'));
    await transactions.add(
      tx('t2', 500, type: TransactionType.income, accountId: 'a'),
    );
    await transactions.add(tx('t3', 999, accountId: 'usd', currency: 'USD'));
    expect(await balances(), {'a': 1200});
    expect(await balances('USD'), {'usd': -992});
    expect(await balances('EUR'), isEmpty);
  });

  test('transactions without account and deleted ones do not count', () async {
    await addAccount('a');
    await transactions.add(tx('t1', 300));
    await transactions.add(tx('t2', 200, accountId: 'a'));
    await transactions.softDelete('t2');
    expect(await balances(), {'a': 0});
  });

  test('a transfer inserted by SQL changes both accounts', () async {
    await addAccount('a', opening: 1000);
    await addAccount('b', opening: 100);
    await transfer('x1', 'a', 'b', 400);
    await transfer('x2', 'b', 'a', 30, deleted: true);
    await transfer('x3', 'a', 'b', 5, currency: 'USD');
    expect(await balances(), {'a': 600, 'b': 500});
  });

  test('stream re-emits after add, edit, delete and undo', () async {
    await addAccount('a', opening: 1000);
    await addAccount('b');
    final seen = <Map<String, int>>[];
    final sub = accounts.watchBalances(currency: 'RUB').listen((m) {
      seen.add({for (final e in m.entries) e.key: e.value.minorUnits});
    });
    addTearDown(sub.cancel);

    await pumpEventQueue();
    expect(seen.last, {'a': 1000, 'b': 0});

    await transactions.add(tx('t1', 300, accountId: 'a'));
    await pumpEventQueue();
    expect(seen.last, {'a': 700, 'b': 0});

    await transactions.update(tx('t1', 400, accountId: 'a')); // сумма
    await pumpEventQueue();
    expect(seen.last, {'a': 600, 'b': 0});

    await transactions.update(
      tx('t1', 400, type: TransactionType.income, accountId: 'a'), // тип
    );
    await pumpEventQueue();
    expect(seen.last, {'a': 1400, 'b': 0});

    await transactions.update(tx('t1', 400, accountId: 'b')); // счёт
    await pumpEventQueue();
    expect(seen.last, {'a': 1000, 'b': -400});

    await transactions.softDelete('t1');
    await pumpEventQueue();
    expect(seen.last, {'a': 1000, 'b': 0});

    await transactions.restore('t1'); // «Отменить»
    await pumpEventQueue();
    expect(seen.last, {'a': 1000, 'b': -400});

    await transfer('x1', 'a', 'b', 100);
    await pumpEventQueue();
    expect(seen.last, {'a': 900, 'b': -300});

    await accounts.setOpeningBalance('a', Money.fromMinor(0, 'RUB'));
    await pumpEventQueue();
    expect(seen.last, {'a': -100, 'b': -300});
  });

  test('balances feed totalOnAccounts (archived excluded)', () async {
    await addAccount('a', opening: 1000);
    await addAccount('b', opening: 500, archivedAt: DateTime.utc(2026, 1, 1));
    final list = await accounts.watchAll().first;
    final map = await accounts.watchBalances(currency: 'RUB').first;
    expect(totalOnAccounts(list, map, currency: 'RUB').minorUnits, 1000);
  });
}
