import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/domain/pace.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

Transaction _tx(
  DateOnly day,
  int minor, {
  TransactionType type = TransactionType.expense,
  String cat = 'c1',
  String? sub,
  String currency = 'RUB',
}) => Transaction(
  id: 'id',
  type: type,
  amount: Money.fromMinor(minor, currency),
  occurredOn: day,
  occurredAt: DateTime.utc(day.year, day.month, day.day, 12),
  categoryId: cat,
  subcategoryId: sub,
);

MonthForecast? _forecast(
  List<Transaction> list,
  DateOnly today, {
  PeriodKind kind = PeriodKind.month,
  AnalyticsPeriod? period,
  String? categoryId,
}) => monthForecast(
  list,
  period ?? currentPeriod(kind, today),
  TransactionType.expense,
  today,
  currency: 'RUB',
  categoryId: categoryId,
);

void main() {
  group('monthForecast', () {
    test('6-е число -> null, 7-е -> прогноз', () {
      final list = [_tx(DateOnly(2026, 10, 1), 600)];
      expect(_forecast(list, DateOnly(2026, 10, 6)), isNull);
      final f = _forecast(list, DateOnly(2026, 10, 7))!;
      expect(f.daysPassed, 7);
      expect(f.spent, Money.fromMinor(600, 'RUB'));
      // 600 * 31 / 7 = 2657,14... -> 2657
      expect(f.forecast, Money.fromMinor(2657, 'RUB'));
      // 600 / 7 = 85,71 -> 86
      expect(f.averagePerDay, Money.fromMinor(86, 'RUB'));
    });

    test('31 день: на 31-е число прогноз равен потраченному', () {
      final f = _forecast([
        _tx(DateOnly(2026, 10, 3), 12345),
      ], DateOnly(2026, 10, 31))!;
      expect(f.daysInMonth, 31);
      expect(f.forecast, f.spent);
    });

    test('февраль 28 и 29 дней', () {
      final f28 = _forecast([
        _tx(DateOnly(2026, 2, 2), 1400),
      ], DateOnly(2026, 2, 14))!;
      expect(f28.daysInMonth, 28);
      expect(f28.forecast, Money.fromMinor(2800, 'RUB'));
      final f29 = _forecast([
        _tx(DateOnly(2028, 2, 2), 1400),
      ], DateOnly(2028, 2, 14))!;
      expect(f29.daysInMonth, 29);
      // 1400 * 29 / 14 = 2900
      expect(f29.forecast, Money.fromMinor(2900, 'RUB'));
    });

    test('прошлый месяц и не месяц -> null', () {
      final today = DateOnly(2026, 10, 20);
      final list = [_tx(DateOnly(2026, 9, 5), 100)];
      final september = currentPeriod(PeriodKind.month, DateOnly(2026, 9, 5));
      expect(_forecast(list, today, period: september), isNull);
      expect(_forecast(list, today, kind: PeriodKind.week), isNull);
      expect(_forecast(list, today, kind: PeriodKind.year), isNull);
      expect(_forecast(list, today, kind: PeriodKind.day), isNull);
      final custom = customPeriod(DateOnly(2026, 10, 1), today, today: today);
      expect(_forecast(list, today, period: custom), isNull);
    });

    test('0 потрачено -> нули', () {
      final f = _forecast([], DateOnly(2026, 10, 15))!;
      expect(f.spent.isZero, isTrue);
      expect(f.averagePerDay.isZero, isTrue);
      expect(f.forecast.isZero, isTrue);
    });

    test('будущие операции месяца, доходы и чужой месяц не считаются', () {
      final today = DateOnly(2026, 10, 10);
      final f = _forecast([
        _tx(DateOnly(2026, 10, 10), 100),
        _tx(DateOnly(2026, 10, 11), 9999),
        _tx(DateOnly(2026, 10, 5), 9999, type: TransactionType.income),
        _tx(DateOnly(2026, 9, 30), 9999),
      ], today)!;
      expect(f.spent, Money.fromMinor(100, 'RUB'));
    });

    test('фильтр по категории включает подкатегории', () {
      final f = _forecast(
        [
          _tx(DateOnly(2026, 10, 1), 100, cat: 'a'),
          _tx(DateOnly(2026, 10, 2), 200, cat: 'a', sub: 's'),
          _tx(DateOnly(2026, 10, 3), 400, cat: 'b'),
        ],
        DateOnly(2026, 10, 10),
        categoryId: 'a',
      )!;
      expect(f.spent, Money.fromMinor(300, 'RUB'));
    });

    test('огромные суммы без переполнения', () {
      const big = 1000000000000000000; // 10^18 копеек
      final f = _forecast([
        _tx(DateOnly(2026, 10, 1), big),
      ], DateOnly(2026, 10, 7))!;
      // Верное значение 4,43e18 влезает в int64: не отрицательное.
      expect(f.forecast.minorUnits, 4428571428571428571);
      final huge = _forecast([
        _tx(DateOnly(2026, 10, 1), 9000000000000000000),
      ], DateOnly(2026, 10, 7))!;
      expect(huge.forecast.minorUnits, 0x7FFFFFFFFFFFFFFF);
    });

    test('другая валюта -> ArgumentError', () {
      expect(
        () => _forecast([
          _tx(DateOnly(2026, 10, 1), 1, currency: 'USD'),
        ], DateOnly(2026, 10, 10)),
        throwsArgumentError,
      );
    });
  });
}
