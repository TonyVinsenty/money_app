import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/home_balance_stream.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/settings/domain/home_balance_line.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../support/fakes.dart';

/// Репозиторий операций с заданными итогами «за всё время» по типу и валюте.
class _Totals extends FakeTransactionsRepository {
  _Totals({this.income = 0, this.expense = 0, this.fail = false});

  final int income;
  final int expense;
  final bool fail;
  final periods = <DateRange>[];

  @override
  Stream<Money> watchTotal({
    required TransactionType type,
    required DateRange period,
    String currency = 'RUB',
  }) {
    periods.add(period);
    if (fail) return Stream.error(StateError('boom'));
    final minor = type == TransactionType.income ? income : expense;
    return Stream.value(Money.fromMinor(minor, currency));
  }
}

Account _account(
  String id,
  String currency,
  int opening, {
  bool archived = false,
}) {
  final account = Account(
    id: id,
    name: 'Счёт $id',
    iconKey: 'wallet',
    openingBalance: Money.fromMinor(opening, currency),
    sortOrder: 0,
    currencyDigits: 2,
  );
  return archived ? account.archived(DateTime.utc(2026, 10, 8)) : account;
}

Stream<Money?> _watch(
  HomeBalanceLine line, {
  String currency = 'RUB',
  _Totals? transactions,
  FakeAccountsRepository? accounts,
}) => watchHomeBalance(
  line: line,
  currency: currency,
  transactions: transactions ?? _Totals(),
  accounts: accounts ?? FakeAccountsRepository(),
);

void main() {
  test('none: строки нет', () async {
    expect(await _watch(HomeBalanceLine.none).first, isNull);
  });

  test('allTime: доходы минус расходы, в валюте, за всё время', () async {
    final repo = _Totals(income: 1000000, expense: 250000);
    final value = await _watch(
      HomeBalanceLine.allTime,
      transactions: repo,
    ).first;

    expect(value, Money.fromMinor(750000, 'RUB'));
    expect(repo.periods, hasLength(2));
    for (final period in repo.periods) {
      expect(period.start.year, 1);
      expect(period.end.year, 9999);
    }
  });

  test('allTime: расходов больше дохода - отрицательная сумма', () async {
    final repo = _Totals(income: 100, expense: 500);
    expect(
      await _watch(HomeBalanceLine.allTime, transactions: repo).first,
      Money.fromMinor(-400, 'RUB'),
    );
  });

  test('allTime: валюта берётся из настройки', () async {
    final repo = _Totals(income: 500);
    expect(
      await _watch(
        HomeBalanceLine.allTime,
        currency: 'USD',
        transactions: repo,
      ).first,
      Money.fromMinor(500, 'USD'),
    );
  });

  test('allTime: ошибка источника уходит в поток ошибкой', () async {
    final repo = _Totals(fail: true);
    await expectLater(
      _watch(HomeBalanceLine.allTime, transactions: repo),
      emitsError(isA<StateError>()),
    );
  });

  group('accounts', () {
    test('сумма по не архивным счетам основной валюты', () async {
      final a = _account('a', 'RUB', 100000);
      final b = _account('b', 'RUB', 5000);
      final archived = _account('c', 'RUB', 999, archived: true);
      final usd = _account('d', 'USD', 7);
      final repo = FakeAccountsRepository(
        accounts: [a, b, archived, usd],
        balances: {
          a.id: Money.fromMinor(120000, 'RUB'),
          b.id: Money.fromMinor(-2000, 'RUB'),
          archived.id: Money.fromMinor(999, 'RUB'),
          usd.id: Money.fromMinor(7, 'USD'),
        },
      );

      expect(
        await _watch(HomeBalanceLine.accounts, accounts: repo).first,
        Money.fromMinor(118000, 'RUB'),
      );
    });

    test('счетов нет - строки нет', () async {
      expect(await _watch(HomeBalanceLine.accounts).first, isNull);
    });

    test('только счёт другой валюты - строки нет', () async {
      final usd = _account('d', 'USD', 7);
      final repo = FakeAccountsRepository(
        accounts: [usd],
        balances: {usd.id: Money.fromMinor(7, 'USD')},
      );
      expect(
        await _watch(HomeBalanceLine.accounts, accounts: repo).first,
        isNull,
      );
    });

    test('только архивный счёт основной валюты - строки нет', () async {
      final old = _account('a', 'RUB', 5, archived: true);
      final repo = FakeAccountsRepository(
        accounts: [old],
        balances: {old.id: Money.fromMinor(5, 'RUB')},
      );
      expect(
        await _watch(HomeBalanceLine.accounts, accounts: repo).first,
        isNull,
      );
    });

    test('счёт с нулевой суммой - ноль, а не отсутствие строки', () async {
      final a = _account('a', 'RUB', 0);
      final repo = FakeAccountsRepository(
        accounts: [a],
        balances: {a.id: Money.zero('RUB')},
      );
      expect(
        await _watch(HomeBalanceLine.accounts, accounts: repo).first,
        Money.zero('RUB'),
      );
    });

    test('ошибка источника уходит в поток ошибкой', () async {
      final repo = FakeAccountsRepository(watchError: StateError('boom'));
      await expectLater(
        _watch(HomeBalanceLine.accounts, accounts: repo),
        emitsError(isA<StateError>()),
      );
    });

    test('новые данные перестраивают сумму', () async {
      final a = _account('a', 'RUB', 100);
      final repo = InMemoryAccountsRepository([a]);
      final live = <Money?>[];
      final liveSub = watchHomeBalance(
        line: HomeBalanceLine.accounts,
        currency: 'RUB',
        transactions: _Totals(),
        accounts: repo,
      ).listen(live.add);
      await Future<void>.delayed(Duration.zero);
      repo.net[a.id] = Money.fromMinor(50, 'RUB');
      await repo.update(a.id, name: 'Новое', iconKey: 'wallet');
      await Future<void>.delayed(Duration.zero);
      await liveSub.cancel();

      // Счета и остатки приходят отдельными событиями: промежуточное значение
      // возможно, итоговое обязано быть верным.
      expect(live.first, Money.fromMinor(100, 'RUB'));
      expect(live.last, Money.fromMinor(150, 'RUB'));
    });
  });

  group('повторная подписка и отписка', () {
    for (final line in HomeBalanceLine.values) {
      test('$line: подписка, отписка и снова подписка работают', () async {
        final a = _account('a', 'RUB', 100);
        final accounts = FakeAccountsRepository(
          accounts: [a],
          balances: {a.id: Money.fromMinor(100, 'RUB')},
        );
        final stream = watchHomeBalance(
          line: line,
          currency: 'RUB',
          transactions: _Totals(income: 30, expense: 10),
          accounts: accounts,
        );
        final expected = switch (line) {
          HomeBalanceLine.none => null,
          HomeBalanceLine.allTime => Money.fromMinor(20, 'RUB'),
          HomeBalanceLine.accounts => Money.fromMinor(100, 'RUB'),
        };

        expect(await stream.first, expected);
        expect(await stream.first, expected);
        final third = <Money?>[];
        final sub = stream.listen(third.add);
        await Future<void>.delayed(Duration.zero);
        await sub.cancel();
        expect(third, [expected]);
      });
    }

    test('закрывается, когда закрылись оба источника', () async {
      final repo = _Tracking();
      var done = false;
      final sub = watchHomeBalance(
        line: HomeBalanceLine.allTime,
        currency: 'RUB',
        transactions: repo,
        accounts: FakeAccountsRepository(),
      ).listen((_) {}, onDone: () => done = true);
      await Future<void>.delayed(Duration.zero);

      await repo.created[0].close();
      await Future<void>.delayed(Duration.zero);
      expect(done, isFalse);
      await repo.created[1].close();
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
      await sub.cancel();
    });

    test('отписка снимает подписки с обоих источников', () async {
      final repo = _Tracking();
      final stream = watchHomeBalance(
        line: HomeBalanceLine.allTime,
        currency: 'RUB',
        transactions: repo,
        accounts: FakeAccountsRepository(),
      );
      final sub = stream.listen((_) {});
      await Future<void>.delayed(Duration.zero);
      expect(repo.created, hasLength(2));
      expect(repo.created.every((c) => c.hasListener), isTrue);

      await sub.cancel();
      expect(repo.created.any((c) => c.hasListener), isFalse);

      // Новый слушатель получает свежие источники.
      final second = stream.listen((_) {});
      await Future<void>.delayed(Duration.zero);
      expect(repo.created, hasLength(4));
      expect(repo.created.skip(2).every((c) => c.hasListener), isTrue);
      await second.cancel();
    });
  });

  test('accounts: остатка для счёта ещё нет - событие пропускается', () async {
    final a = _account('a', 'RUB', 100);
    final accountsController = StreamController<List<Account>>();
    final balancesController = StreamController<Map<String, Money>>();
    final repo = _LiveAccounts(
      accountsController.stream,
      balancesController.stream,
    );
    final values = <Money?>[];
    final errors = <Object>[];
    final sub = watchHomeBalance(
      line: HomeBalanceLine.accounts,
      currency: 'RUB',
      transactions: _Totals(),
      accounts: repo,
    ).listen(values.add, onError: errors.add);

    accountsController.add([a]);
    balancesController.add(const {});
    await Future<void>.delayed(Duration.zero);
    expect(values, isEmpty);
    expect(errors, isEmpty);

    balancesController.add({a.id: Money.fromMinor(100, 'RUB')});
    await Future<void>.delayed(Duration.zero);
    expect(values, [Money.fromMinor(100, 'RUB')]);
    expect(errors, isEmpty);
    await sub.cancel();
    await accountsController.close();
    await balancesController.close();
  });
}

/// Репозиторий, который запоминает созданные потоки итогов.
class _Tracking extends FakeTransactionsRepository {
  final created = <StreamController<Money>>[];

  @override
  Stream<Money> watchTotal({
    required TransactionType type,
    required DateRange period,
    String currency = 'RUB',
  }) {
    final controller = StreamController<Money>();
    created.add(controller);
    return controller.stream;
  }
}

class _LiveAccounts extends FakeAccountsRepository {
  _LiveAccounts(this._accounts, this._balances);

  final Stream<List<Account>> _accounts;
  final Stream<Map<String, Money>> _balances;

  @override
  Stream<List<Account>> watchAll() => _accounts;

  @override
  Stream<Map<String, Money>> watchBalances() => _balances;
}
