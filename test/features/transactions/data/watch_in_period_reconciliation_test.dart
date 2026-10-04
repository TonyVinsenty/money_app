import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/period_summary.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/fixture_transactions.dart';
import '../../../support/load_fixture_into_db.dart';

/// Сверка двух путей подсчёта (ADR 0007, п. 2): «Аналитика» считает итоги в
/// `domain` по списку из `watchInPeriod`, «Главная» — суммой в SQL через
/// `watchTotal`. На одном тестовом наборе результаты обязаны совпасть.
void main() {
  group('сверка на тестовом наборе test_dataset_two_months.csv', () {
    late AppDatabase db;
    late DriftTransactionsRepository repo;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      repo = DriftTransactionsRepository(db);
      await loadFixtureIntoDatabase(db, loadFixtureTransactions());
    });

    tearDown(() async {
      await db.close();
    });

    Future<Money> totalOf(TransactionType type, DateRange period) =>
        repo.watchTotal(type: type, period: period).first;

    test('сентябрь 2026: summarizePeriod(watchInPeriod) = watchTotal, '
        'и обе суммы совпадают с зафиксированными', () async {
      final september = monthRange(DateOnly(2026, 9, 1));

      final list = await repo.watchInPeriod(september).first;
      final summary = summarizePeriod(list, september, currency: 'RUB');

      final sqlExpense = await totalOf(TransactionType.expense, september);
      final sqlIncome = await totalOf(TransactionType.income, september);

      // Зафиксированные суммы (копейки): 128 033,88 расходов и 102 949,00
      // доходов. Баланс: 102 949,00 - 128 033,88 = -25 084,88.
      expect(sqlExpense, Money.fromMinor(12803388, 'RUB'));
      expect(sqlIncome, Money.fromMinor(10294900, 'RUB'));

      expect(summary.expense, sqlExpense);
      expect(summary.income, sqlIncome);
      expect(summary.balance.minorUnits, 10294900 - 12803388);
      expect(summary.balance.minorUnits, -2508488);
    });

    test(
      'сентябрь 2026: число операций в списке совпадает с набором',
      () async {
        final september = monthRange(DateOnly(2026, 9, 1));

        final list = await repo.watchInPeriod(september).first;
        final expected = loadFixtureTransactions()
            .where((t) => t.occurredOn.month == 9)
            .length;

        expect(list, hasLength(expected));
        expect(
          summarizePeriod(list, september, currency: 'RUB').count,
          expected,
        );
      },
    );

    test('октябрь 2026 (до 4 октября): итоги совпадают с SQL и с '
        'зафиксированными суммами', () async {
      final october = monthRange(DateOnly(2026, 10, 1));

      final list = await repo.watchInPeriod(october).first;
      final summary = summarizePeriod(list, october, currency: 'RUB');

      expect(
        await totalOf(TransactionType.expense, october),
        Money.fromMinor(3401287, 'RUB'),
      );
      expect(
        await totalOf(TransactionType.income, october),
        Money.fromMinor(9045700, 'RUB'),
      );
      expect(summary.expense, Money.fromMinor(3401287, 'RUB'));
      expect(summary.income, Money.fromMinor(9045700, 'RUB'));
    });
  });
}
