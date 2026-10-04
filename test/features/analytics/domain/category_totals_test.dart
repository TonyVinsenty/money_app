import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/category_totals.dart';
import 'package:money_app/features/analytics/domain/period_summary.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/fixture_transactions.dart';

final _september = DateRange(DateOnly(2026, 9, 1), DateOnly(2026, 9, 30));

/// Сентябрь 2026 из тестового набора (зафиксировано по набору, копейки).
/// «Продукты» (`cat-food`): 38 102,48 — 27 операций. Из них без подкатегории
/// 5 642,20 (7 операций), «Овощи» (`sub-food-veg`) 14 975,81 (11 операций),
/// `sub-food-5` 17 484,47 (9 операций).
const _septemberFoodMinor = 3810248;
const _septemberFoodCount = 27;
const _septemberFoodNoSubMinor = 564220;
const _septemberFoodVegMinor = 1497581;
const _septemberFoodSub5Minor = 1748447;
const _septemberIncomeMinor = 10294900;

/// Операция в рублях. Id и момент не важны для итогов.
Transaction _tx(
  TransactionType type,
  int minorUnits,
  DateOnly day, {
  String categoryId = 'cat-test',
  String? subcategoryId,
  String currency = 'RUB',
}) {
  return Transaction(
    id: 'test-id',
    type: type,
    amount: Money.fromMinor(minorUnits, currency),
    occurredOn: day,
    occurredAt: DateTime.utc(day.year, day.month, day.day, 12),
    categoryId: categoryId,
    subcategoryId: subcategoryId,
  );
}

void main() {
  final all = loadFixtureTransactions();

  group('totalsByCategory на тестовом наборе', () {
    test('«Продукты» за сентябрь: сумма и число операций', () {
      final totals = totalsByCategory(
        all,
        _september,
        type: TransactionType.expense,
        currency: 'RUB',
      );
      final food = totals.singleWhere((t) => t.categoryId == 'cat-food');

      expect(food.amount, Money.fromMinor(_septemberFoodMinor, 'RUB'));
      expect(food.count, _septemberFoodCount);
    });

    test('сумма всех категорий = итог расходов из summarizePeriod', () {
      final totals = totalsByCategory(
        all,
        _september,
        type: TransactionType.expense,
        currency: 'RUB',
      );
      final summary = summarizePeriod(all, _september, currency: 'RUB');

      final sum = totals.fold(Money.zero('RUB'), (a, t) => a + t.amount);
      final count = totals.fold(0, (a, t) => a + t.count);
      expect(sum, summary.expense);
      expect(count, summary.expenseCount);
    });

    test('тип «доход» считает только доходы', () {
      final totals = totalsByCategory(
        all,
        _september,
        type: TransactionType.income,
        currency: 'RUB',
      );
      final sum = totals.fold(Money.zero('RUB'), (a, t) => a + t.amount);

      expect(sum, Money.fromMinor(_septemberIncomeMinor, 'RUB'));
      expect(totals.map((t) => t.categoryId), everyElement(startsWith('inc-')));
    });

    test('порядок: по убыванию суммы', () {
      final totals = totalsByCategory(
        all,
        _september,
        type: TransactionType.expense,
        currency: 'RUB',
      );

      for (var i = 1; i < totals.length; i++) {
        expect(
          totals[i - 1].amount >= totals[i].amount,
          isTrue,
          reason: '${totals[i - 1].categoryId} < ${totals[i].categoryId}',
        );
      }
    });

    test('при равной сумме порядок по id категории и устойчив', () {
      final transactions = [
        _tx(
          TransactionType.expense,
          500,
          DateOnly(2026, 9, 2),
          categoryId: 'cat-b',
        ),
        _tx(
          TransactionType.expense,
          500,
          DateOnly(2026, 9, 3),
          categoryId: 'cat-a',
        ),
        _tx(
          TransactionType.expense,
          900,
          DateOnly(2026, 9, 4),
          categoryId: 'cat-c',
        ),
      ];

      final totals = totalsByCategory(
        transactions,
        _september,
        type: TransactionType.expense,
        currency: 'RUB',
      );

      expect(totals.map((t) => t.categoryId), ['cat-c', 'cat-a', 'cat-b']);
    });

    test('категория, где только операции на 0,00, не попадает в список', () {
      final transactions = [
        _tx(
          TransactionType.expense,
          0,
          DateOnly(2026, 9, 2),
          categoryId: 'cat-zero',
        ),
        _tx(
          TransactionType.expense,
          700,
          DateOnly(2026, 9, 3),
          categoryId: 'cat-real',
        ),
      ];

      final totals = totalsByCategory(
        transactions,
        _september,
        type: TransactionType.expense,
        currency: 'RUB',
      );

      expect(totals.map((t) => t.categoryId), ['cat-real']);
    });

    test('категория вне периода не попадает в список', () {
      final transactions = [
        _tx(
          TransactionType.expense,
          700,
          DateOnly(2026, 8, 31),
          categoryId: 'cat-august',
        ),
        _tx(
          TransactionType.expense,
          300,
          DateOnly(2026, 9, 1),
          categoryId: 'cat-september',
        ),
      ];

      final totals = totalsByCategory(
        transactions,
        _september,
        type: TransactionType.expense,
        currency: 'RUB',
      );

      expect(totals.map((t) => t.categoryId), ['cat-september']);
    });

    test('операция в другой валюте — ArgumentError, даже вне периода', () {
      final transactions = [
        _tx(TransactionType.expense, 100, DateOnly(2026, 9, 2)),
        _tx(
          TransactionType.expense,
          100,
          DateOnly(2026, 8, 2),
          currency: 'USD',
        ),
      ];

      expect(
        () => totalsByCategory(
          transactions,
          _september,
          type: TransactionType.expense,
          currency: 'RUB',
        ),
        throwsArgumentError,
      );
    });
  });

  group('subcategoryTotals: смешение валют', () {
    test('операция в другой валюте — ArgumentError, даже вне периода', () {
      final transactions = [
        _tx(TransactionType.expense, 100, DateOnly(2026, 9, 2)),
        _tx(
          TransactionType.expense,
          100,
          DateOnly(2026, 8, 2),
          currency: 'USD',
        ),
      ];

      expect(
        () => subcategoryTotals(
          transactions,
          _september,
          categoryId: 'cat-test',
          currency: 'RUB',
        ),
        throwsArgumentError,
      );
    });
  });

  group('subcategoryTotals на тестовом наборе', () {
    test('подкатегории «Продуктов» в сумме дают итог категории', () {
      final subs = subcategoryTotals(
        all,
        _september,
        categoryId: 'cat-food',
        currency: 'RUB',
      );
      final sum = subs.fold(Money.zero('RUB'), (a, s) => a + s.amount);

      expect(sum, Money.fromMinor(_septemberFoodMinor, 'RUB'));
      expect(subs.fold(0, (a, s) => a + s.count), _septemberFoodCount);
    });

    test('суммы подкатегорий «Продуктов» совпадают с набором', () {
      final subs = subcategoryTotals(
        all,
        _september,
        categoryId: 'cat-food',
        currency: 'RUB',
      );
      final byId = {for (final s in subs) s.subcategoryId: s.amount};

      expect(byId[null], Money.fromMinor(_septemberFoodNoSubMinor, 'RUB'));
      expect(
        byId['sub-food-veg'],
        Money.fromMinor(_septemberFoodVegMinor, 'RUB'),
      );
      expect(
        byId['sub-food-5'],
        Money.fromMinor(_septemberFoodSub5Minor, 'RUB'),
      );
    });

    test('группа «без подкатегории» есть, когда у части операций её нет', () {
      final subs = subcategoryTotals(
        all,
        _september,
        categoryId: 'cat-food',
        currency: 'RUB',
      );

      expect(subs.map((s) => s.subcategoryId), contains(null));
    });

    test('группы «без подкатегории» нет, если у всех операций она выбрана', () {
      final transactions = [
        _tx(
          TransactionType.expense,
          400,
          DateOnly(2026, 9, 2),
          categoryId: 'cat-food',
          subcategoryId: 'sub-veg',
        ),
        _tx(
          TransactionType.expense,
          600,
          DateOnly(2026, 9, 3),
          categoryId: 'cat-food',
          subcategoryId: 'sub-meat',
        ),
      ];

      final subs = subcategoryTotals(
        transactions,
        _september,
        categoryId: 'cat-food',
        currency: 'RUB',
      );

      expect(subs.map((s) => s.subcategoryId), ['sub-meat', 'sub-veg']);
    });

    test(
      'порядок: по сумме, при равенстве по id; «без подкатегории» последней',
      () {
        final transactions = [
          _tx(
            TransactionType.expense,
            500,
            DateOnly(2026, 9, 2),
            categoryId: 'cat-food',
          ),
          _tx(
            TransactionType.expense,
            500,
            DateOnly(2026, 9, 3),
            categoryId: 'cat-food',
            subcategoryId: 'sub-b',
          ),
          _tx(
            TransactionType.expense,
            500,
            DateOnly(2026, 9, 4),
            categoryId: 'cat-food',
            subcategoryId: 'sub-a',
          ),
          _tx(
            TransactionType.expense,
            900,
            DateOnly(2026, 9, 5),
            categoryId: 'cat-food',
            subcategoryId: 'sub-c',
          ),
        ];

        final subs = subcategoryTotals(
          transactions,
          _september,
          categoryId: 'cat-food',
          currency: 'RUB',
        );

        expect(subs.map((s) => s.subcategoryId), [
          'sub-c',
          'sub-a',
          'sub-b',
          null,
        ]);
      },
    );

    test('подкатегория, где только операции на 0,00, не попадает в список', () {
      final transactions = [
        _tx(
          TransactionType.expense,
          0,
          DateOnly(2026, 9, 2),
          categoryId: 'cat-food',
          subcategoryId: 'sub-zero',
        ),
        _tx(
          TransactionType.expense,
          300,
          DateOnly(2026, 9, 3),
          categoryId: 'cat-food',
          subcategoryId: 'sub-real',
        ),
      ];

      final subs = subcategoryTotals(
        transactions,
        _september,
        categoryId: 'cat-food',
        currency: 'RUB',
      );

      expect(subs.map((s) => s.subcategoryId), ['sub-real']);
    });

    test('другие категории в подсчёт не попадают', () {
      final subs = subcategoryTotals(
        all,
        _september,
        categoryId: 'cat-transport',
        currency: 'RUB',
      );
      final sum = subs.fold(Money.zero('RUB'), (a, s) => a + s.amount);

      expect(sum, Money.fromMinor(268575, 'RUB'));
    });
  });
}
