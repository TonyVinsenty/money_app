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
      // Первая операция 1-го: 600 / 7 = 85,71 -> 86; 600 + 86 * 24 = 2664
      expect(f.averagePerDay, Money.fromMinor(86, 'RUB'));
      expect(f.forecast, Money.fromMinor(2664, 'RUB'));
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
      // 1400 за 13 дней (с 2-го по 14-е) -> 108 в день; 1400 + 108 * 14
      expect(f28.forecast, Money.fromMinor(2912, 'RUB'));
      final f29 = _forecast([
        _tx(DateOnly(2028, 2, 2), 1400),
      ], DateOnly(2028, 2, 14))!;
      expect(f29.daysInMonth, 29);
      // 1400 + 108 * 15 = 3020
      expect(f29.forecast, Money.fromMinor(3020, 'RUB'));
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

    test('0 потрачено по сегодня -> null', () {
      expect(_forecast([], DateOnly(2026, 10, 15)), isNull);
    });

    test('только будущие операции -> null', () {
      expect(
        _forecast([_tx(DateOnly(2026, 10, 20), 500)], DateOnly(2026, 10, 15)),
        isNull,
      );
    });

    test('3000 ₽ с 8-го по 10-е: 1000 ₽ в день, прогноз 24 000 ₽', () {
      final f = _forecast([
        _tx(DateOnly(2026, 10, 8), 100000),
        _tx(DateOnly(2026, 10, 9), 100000),
        _tx(DateOnly(2026, 10, 10), 100000),
      ], DateOnly(2026, 10, 10))!;
      expect(f.spent, Money.fromMinor(300000, 'RUB'));
      expect(f.averagePerDay, Money.fromMinor(100000, 'RUB'));
      // 3000 + 1000 * 21 оставшихся дней
      expect(f.forecast, Money.fromMinor(2400000, 'RUB'));
    });

    test('будущая операция больше прогноза -> итог месяца', () {
      final f = _forecast([
        _tx(DateOnly(2026, 10, 1), 1000),
        _tx(DateOnly(2026, 10, 25), 900000),
      ], DateOnly(2026, 10, 10))!;
      expect(f.spent, Money.fromMinor(1000, 'RUB'));
      expect(f.forecast, Money.fromMinor(901000, 'RUB'));
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
      // 10^18 + (10^18 / 7 = 142857142857142857) * 24
      expect(f.forecast.minorUnits, 4428571428571428568);
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
