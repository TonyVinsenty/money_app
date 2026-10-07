import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/account_balances.dart';

Money rub(int minor) => Money.fromMinor(minor, 'RUB');

Account acc(String id, int opening, {bool archived = false}) => Account(
  id: id,
  name: 'Счёт $id',
  iconKey: 'card',
  openingBalance: rub(opening),
  sortOrder: 0,
  archivedAt: archived ? DateTime.utc(2026, 10, 7) : null,
);

AccountFlows flows({
  int income = 0,
  int expense = 0,
  int inn = 0,
  int out = 0,
}) => AccountFlows(
  income: rub(income),
  expense: rub(expense),
  transfersIn: rub(inn),
  transfersOut: rub(out),
);

void main() {
  group('AccountFlows', () {
    test('net: доходы + переводы на - расходы - переводы со', () {
      expect(flows(income: 1000, expense: 300, inn: 50, out: 20).net, rub(730));
    });

    test('none — нули в нужной валюте', () {
      final none = AccountFlows.none('USD');
      expect(none.currency, 'USD');
      expect(none.net, Money.zero('USD'));
    });

    test('разные валюты внутри — ArgumentError', () {
      expect(
        () => AccountFlows(
          income: rub(1),
          expense: Money.fromMinor(1, 'USD'),
          transfersIn: rub(0),
          transfersOut: rub(0),
        ),
        throwsArgumentError,
      );
    });

    test('отрицательная сумма движений — ArgumentError', () {
      expect(() => flows(income: -1), throwsArgumentError);
      expect(() => flows(expense: -1), throwsArgumentError);
      expect(() => flows(inn: -1), throwsArgumentError);
      expect(() => flows(out: -1), throwsArgumentError);
    });

    test('равенство и hashCode', () {
      expect(flows(income: 1), flows(income: 1));
      expect(flows(income: 1).hashCode, flows(income: 1).hashCode);
      expect(flows(income: 1) == flows(expense: 1), isFalse);
      expect(flows().toString(), contains('AccountFlows'));
    });
  });

  group('computeAccountBalances', () {
    test('без движений остаток равен стартовому', () {
      final result = computeAccountBalances([acc('a', 1234)], {});
      expect(result, {'a': rub(1234)});
    });

    test('все четыре вида движений', () {
      final result = computeAccountBalances(
        [acc('a', 10000)],
        {'a': flows(income: 5000, expense: 2000, inn: 700, out: 300)},
      );
      expect(result['a'], rub(10000 + 5000 - 2000 + 700 - 300));
    });

    test('итог может быть отрицательным', () {
      final result = computeAccountBalances(
        [acc('a', 100), acc('b', -500)],
        {'a': flows(expense: 1000), 'b': flows(income: 100)},
      );
      expect(result['a'], rub(-900));
      expect(result['b'], rub(-400));
    });

    test('архивный счёт тоже считается', () {
      final result = computeAccountBalances(
        [acc('a', 100, archived: true)],
        {'a': flows(income: 50)},
      );
      expect(result['a'], rub(150));
    });

    test('движения несуществующего счёта игнорируются', () {
      final result = computeAccountBalances(
        [acc('a', 1)],
        {'zzz': flows(income: 99)},
      );
      expect(result, {'a': rub(1)});
    });

    test('другая валюта — ArgumentError', () {
      expect(
        () => computeAccountBalances(
          [acc('a', 1)],
          {'a': AccountFlows.none('USD')},
        ),
        throwsArgumentError,
      );
    });

    test('суммы около 10^14 копеек считаются точно', () {
      const big = 100000000000000;
      final result = computeAccountBalances(
        [acc('a', big)],
        {'a': flows(income: big, expense: 1, inn: big, out: 2)},
      );
      expect(result['a']!.minorUnits, 3 * big - 3);
    });
  });

  group('totalOnAccounts', () {
    test('архивный не входит, но его остаток посчитан', () {
      final accounts = [
        acc('a', 100),
        acc('b', 200, archived: true),
        acc('c', -50),
      ];
      final balances = computeAccountBalances(accounts, {});
      expect(balances['b'], rub(200));
      expect(totalOnAccounts(accounts, balances, currency: 'RUB'), rub(50));
    });

    test('нет счетов — ноль', () {
      expect(totalOnAccounts([], {}, currency: 'RUB'), Money.zero('RUB'));
    });

    test('все архивные — ноль', () {
      final accounts = [acc('a', 100, archived: true)];
      expect(
        totalOnAccounts(
          accounts,
          computeAccountBalances(accounts, {}),
          currency: 'RUB',
        ),
        Money.zero('RUB'),
      );
    });

    test('нет остатка для не архивного счёта — ArgumentError', () {
      expect(
        () => totalOnAccounts([acc('a', 1)], {}, currency: 'RUB'),
        throwsArgumentError,
      );
    });

    test('счета другой валюты (и архивные тоже) пропускаются', () {
      final usd = Account(
        id: 'u',
        name: 'USD',
        iconKey: 'card',
        openingBalance: Money.fromMinor(999, 'USD'),
        sortOrder: 0,
      );
      final usdArchived = Account(
        id: 'ua',
        name: 'USD old',
        iconKey: 'card',
        openingBalance: Money.fromMinor(5, 'USD'),
        sortOrder: 0,
        archivedAt: DateTime.utc(2026, 10, 7),
      );
      final accounts = [acc('a', 100), usd, usdArchived];
      final balances = computeAccountBalances(accounts, {});

      expect(totalOnAccounts(accounts, balances, currency: 'RUB'), rub(100));
      expect(
        totalOnAccounts(accounts, balances, currency: 'USD'),
        Money.fromMinor(999, 'USD'),
      );
      expect(
        totalOnAccounts(accounts, balances, currency: 'EUR'),
        Money.zero('EUR'),
      );
    });
  });

  group('openingForCurrentBalance', () {
    test('без движений стартовый равен введённому', () {
      expect(
        openingForCurrentBalance(rub(777), AccountFlows.none('RUB')),
        rub(777),
      );
    });

    test('после поправки остаток ровно равен введённому', () {
      final f = flows(income: 5000, expense: 12000, inn: 300, out: 100);
      for (final entered in [0, 1, 99999, -2500]) {
        final opening = openingForCurrentBalance(rub(entered), f);
        final account = acc('a', 0).withOpeningBalance(opening);
        final balance = computeAccountBalances([account], {'a': f})['a'];
        expect(balance, rub(entered));
      }
    });

    test('суммы около 10^14 копеек', () {
      const big = 100000000000000;
      final f = flows(income: big, expense: 1);
      final opening = openingForCurrentBalance(rub(big), f);
      expect(opening, rub(1));
    });

    test('другая валюта — ArgumentError', () {
      expect(
        () => openingForCurrentBalance(rub(1), AccountFlows.none('USD')),
        throwsArgumentError,
      );
    });
  });
}
