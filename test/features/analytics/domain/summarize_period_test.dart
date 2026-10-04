import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/period_summary.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/fixture_transactions.dart';

final _september = DateRange(DateOnly(2026, 9, 1), DateOnly(2026, 9, 30));
final _firstFourOctober = DateRange(
  DateOnly(2026, 10, 1),
  DateOnly(2026, 10, 4),
);

/// Операция в рублях на указанный день. Id и момент не важны для итогов.
Transaction _tx(
  TransactionType type,
  int minorUnits,
  DateOnly day, {
  String currency = 'RUB',
}) {
  return Transaction(
    id: 'test-id',
    type: type,
    amount: Money.fromMinor(minorUnits, currency),
    occurredOn: day,
    occurredAt: DateTime.utc(day.year, day.month, day.day, 12),
    categoryId: 'cat-test',
  );
}

void main() {
  group('помощник загрузки тестового набора', () {
    test('читает 131 операцию', () {
      expect(loadFixtureTransactions(), hasLength(131));
    });
  });

  group('summarizePeriod на тестовом наборе', () {
    final all = loadFixtureTransactions();

    test('сентябрь 2026: доходы, расходы и отрицательный баланс', () {
      final summary = summarizePeriod(all, _september, currency: 'RUB');

      expect(summary.income, Money.fromMinor(10294900, 'RUB'));
      expect(summary.expense, Money.fromMinor(12803388, 'RUB'));
      expect(summary.balance, Money.fromMinor(-2508488, 'RUB'));
      expect(summary.balance.isNegative, isTrue);
    });

    test('1–4 октября 2026: доходы и расходы', () {
      final summary = summarizePeriod(all, _firstFourOctober, currency: 'RUB');

      expect(summary.income, Money.fromMinor(9045700, 'RUB'));
      expect(summary.expense, Money.fromMinor(3401287, 'RUB'));
    });

    test('количества по видам складываются в общее число операций', () {
      final summary = summarizePeriod(all, _september, currency: 'RUB');

      expect(summary.incomeCount + summary.expenseCount, summary.count);
      // В сентябре в тестовом наборе 109 операций (все в рублях).
      expect(summary.count, 109);
    });
  });

  group('границы периода', () {
    test('первый и последний день входят, соседние дни — нет', () {
      final transactions = [
        _tx(TransactionType.expense, 100, DateOnly(2026, 8, 31)),
        _tx(TransactionType.expense, 200, DateOnly(2026, 9, 1)),
        _tx(TransactionType.expense, 300, DateOnly(2026, 9, 30)),
        _tx(TransactionType.expense, 400, DateOnly(2026, 10, 1)),
      ];

      final summary = summarizePeriod(
        transactions,
        _september,
        currency: 'RUB',
      );

      expect(summary.expenseCount, 2);
      expect(summary.expense, Money.fromMinor(500, 'RUB'));
    });
  });

  group('крайние случаи', () {
    test('пустой список: все нули и 0 операций', () {
      final summary = summarizePeriod([], _september, currency: 'RUB');

      expect(summary.income, Money.zero('RUB'));
      expect(summary.expense, Money.zero('RUB'));
      expect(summary.balance, Money.zero('RUB'));
      expect(summary.count, 0);
    });

    test('период без операций: все нули, даже если набор не пуст', () {
      final summary = summarizePeriod(
        loadFixtureTransactions(),
        DateRange(DateOnly(2020, 1, 1), DateOnly(2020, 1, 31)),
        currency: 'RUB',
      );

      expect(summary.balance, Money.zero('RUB'));
      expect(summary.count, 0);
    });

    test('только расходы: баланс равен минус расходам', () {
      final transactions = [
        _tx(TransactionType.expense, 10000, DateOnly(2026, 9, 5)),
        _tx(TransactionType.expense, 5050, DateOnly(2026, 9, 6)),
      ];

      final summary = summarizePeriod(
        transactions,
        _september,
        currency: 'RUB',
      );

      expect(summary.income, Money.zero('RUB'));
      expect(summary.expense, Money.fromMinor(15050, 'RUB'));
      expect(summary.balance, -summary.expense);
      expect(summary.balance, Money.fromMinor(-15050, 'RUB'));
    });

    test('операция на 0,00 считается в количестве, но не в суммах', () {
      final transactions = [
        _tx(TransactionType.income, 0, DateOnly(2026, 9, 2)),
        _tx(TransactionType.expense, 0, DateOnly(2026, 9, 3)),
        _tx(TransactionType.expense, 700, DateOnly(2026, 9, 4)),
      ];

      final summary = summarizePeriod(
        transactions,
        _september,
        currency: 'RUB',
      );

      expect(summary.incomeCount, 1);
      expect(summary.expenseCount, 2);
      expect(summary.count, 3);
      expect(summary.income, Money.zero('RUB'));
      expect(summary.expense, Money.fromMinor(700, 'RUB'));
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
        () => summarizePeriod(transactions, _september, currency: 'RUB'),
        throwsArgumentError,
      );
    });
  });
}
