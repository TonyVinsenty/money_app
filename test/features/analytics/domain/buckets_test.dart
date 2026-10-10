import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/domain/buckets.dart';
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

List<Bucket> _totals(
  List<Transaction> list,
  AnalyticsPeriod p, {
  TransactionType type = TransactionType.expense,
  String? categoryId,
}) =>
    bucketTotals(list, p, type: type, currency: 'RUB', categoryId: categoryId);

AnalyticsPeriod _custom(DateOnly start, int days) {
  final end = start.addDays(days - 1);
  return customPeriod(start, end, today: end);
}

int _sum(List<Bucket> b) => b.fold(0, (s, x) => s + x.amount.minorUnits);

void main() {
  final today = DateOnly(2026, 10, 11);
  final october = currentPeriod(PeriodKind.month, today);

  group('bucketTotals', () {
    test('октябрь: 31 корзина-день, сумма корзин = итог', () {
      final list = [
        _tx(DateOnly(2026, 10, 1), 100),
        _tx(DateOnly(2026, 10, 1), 50),
        _tx(DateOnly(2026, 10, 31), 700),
        _tx(DateOnly(2026, 9, 30), 999), // вне периода
        _tx(DateOnly(2026, 10, 5), 300, type: TransactionType.income),
      ];
      final b = _totals(list, october);
      expect(b, hasLength(31));
      expect(b.first.range, dayRange(DateOnly(2026, 10, 1)));
      expect(b.first.amount.minorUnits, 150);
      expect(b[1].amount.isZero, isTrue);
      expect(b.last.range, dayRange(DateOnly(2026, 10, 31)));
      expect(_sum(b), 850);
    });

    test('доходы считаются отдельно', () {
      final list = [
        _tx(DateOnly(2026, 10, 5), 300, type: TransactionType.income),
        _tx(DateOnly(2026, 10, 5), 10),
      ];
      expect(_sum(_totals(list, october, type: TransactionType.income)), 300);
    });

    test('неделя: 7 корзин', () {
      final w = currentPeriod(PeriodKind.week, today);
      expect(_totals([], w), hasLength(7));
    });

    test('год: 12 месяцев, сумма = итог', () {
      final y = currentPeriod(PeriodKind.year, today);
      final b = _totals([
        _tx(DateOnly(2026, 1, 1), 10),
        _tx(DateOnly(2026, 2, 28), 20),
        _tx(DateOnly(2026, 12, 31), 30),
      ], y);
      expect(b, hasLength(12));
      expect(b[1].range, monthRange(DateOnly(2026, 2, 1)));
      expect(b[1].amount.minorUnits, 20);
      expect(_sum(b), 60);
    });

    test('свой 62 дня — дни, 63 дня — месяцы', () {
      final start = DateOnly(2026, 8, 20);
      expect(bucketStepFor(_custom(start, 62)), BucketStep.day);
      expect(_totals([], _custom(start, 62)), hasLength(62));
      expect(bucketStepFor(_custom(start, 63)), BucketStep.month);
      expect(_totals([], _custom(start, 63)), hasLength(3)); // авг, сен, окт
    });

    test('свой 63 дня: крайние месяцы обрезаны границами', () {
      final p = _custom(DateOnly(2026, 8, 20), 63); // 20.08 - 21.10
      final b = _totals([
        _tx(DateOnly(2026, 8, 20), 1),
        _tx(DateOnly(2026, 10, 21), 2),
        _tx(DateOnly(2026, 10, 22), 4), // вне периода
      ], p);
      expect(
        b.first.range,
        DateRange(DateOnly(2026, 8, 20), DateOnly(2026, 8, 31)),
      );
      expect(b[1].range, monthRange(DateOnly(2026, 9, 1)));
      expect(
        b.last.range,
        DateRange(DateOnly(2026, 10, 1), DateOnly(2026, 10, 21)),
      );
      expect(_sum(b), 3);
    });

    test('день — корзин нет', () {
      final d = currentPeriod(PeriodKind.day, today);
      expect(bucketStepFor(d), BucketStep.none);
      expect(_totals([_tx(today, 5)], d), isEmpty);
    });

    test('пустой период — нулевые корзины', () {
      final b = _totals([], october);
      expect(b, hasLength(31));
      expect(_sum(b), 0);
    });

    test('фильтр по категории включает подкатегории', () {
      final list = [
        _tx(DateOnly(2026, 10, 2), 100, cat: 'c1'),
        _tx(DateOnly(2026, 10, 2), 40, cat: 'c1', sub: 's1'),
        _tx(DateOnly(2026, 10, 2), 900, cat: 'c2'),
      ];
      final b = _totals(list, october, categoryId: 'c1');
      expect(b[1].amount.minorUnits, 140);
      expect(_sum(b), 140);
    });

    test('другая валюта — ArgumentError', () {
      expect(
        () => _totals([_tx(today, 1, currency: 'USD')], october),
        throwsArgumentError,
      );
    });
  });

  group('bucketAverage', () {
    test('текущий месяц, 11 октября: делит на 11', () {
      final b = _totals([
        _tx(DateOnly(2026, 10, 1), 1100),
        _tx(DateOnly(2026, 10, 11), 100),
      ], october);
      expect(bucketAverage(b, today), Money.fromMinor(109, 'RUB')); // 1200/11
    });

    test('прошедший месяц — делит на все корзины', () {
      final b = _totals([
        _tx(DateOnly(2026, 9, 1), 3000),
      ], currentPeriod(PeriodKind.month, DateOnly(2026, 9, 5)));
      expect(bucketAverage(b, today), Money.fromMinor(100, 'RUB'));
    });

    test('текущий год: считаются месяцы по текущий включительно', () {
      final b = _totals([
        _tx(DateOnly(2026, 1, 5), 1000),
      ], currentPeriod(PeriodKind.year, today));
      expect(bucketAverage(b, today), Money.fromMinor(100, 'RUB')); // /10
    });

    test('округление половины от нуля', () {
      final p = currentPeriod(PeriodKind.week, DateOnly(2026, 10, 5)); // 5-11
      final b = _totals([_tx(DateOnly(2026, 10, 5), 5)], p);
      expect(
        bucketAverage(b, DateOnly(2026, 10, 6)),
        Money.fromMinor(3, 'RUB'),
      ); // 5/2
    });

    test('нет корзин — null', () {
      expect(bucketAverage([], today), isNull);
      final d = _totals([], currentPeriod(PeriodKind.day, today));
      expect(bucketAverage(d, today), isNull);
    });
  });
}
