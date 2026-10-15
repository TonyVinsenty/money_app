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

    test('свой интервал через Новый год 15.12-20.02: 68 дней, по месяцам', () {
      final p = customPeriod(
        DateOnly(2025, 12, 15),
        DateOnly(2026, 2, 20),
        today: DateOnly(2026, 2, 20),
      );
      expect(p.range.lengthInDays, 68);
      expect(bucketStepFor(p), BucketStep.month);
      final b = _totals([
        _tx(DateOnly(2025, 12, 31), 1),
        _tx(DateOnly(2026, 1, 1), 2),
        _tx(DateOnly(2026, 2, 20), 4),
        _tx(DateOnly(2025, 12, 14), 8), // вне периода
      ], p);
      expect(b, hasLength(3));
      expect(
        b.first.range,
        DateRange(DateOnly(2025, 12, 15), DateOnly(2025, 12, 31)),
      );
      expect(b[1].range, monthRange(DateOnly(2026, 1, 1)));
      expect(
        b.last.range,
        DateRange(DateOnly(2026, 2, 1), DateOnly(2026, 2, 20)),
      );
      expect([for (final x in b) x.amount.minorUnits], [1, 2, 4]);
    });

    test('февраль 2028 (високосный): 29 корзин', () {
      final p = currentPeriod(PeriodKind.month, DateOnly(2028, 2, 10));
      final b = _totals([_tx(DateOnly(2028, 2, 29), 7)], p);
      expect(b, hasLength(29));
      expect(b.last.range, dayRange(DateOnly(2028, 2, 29)));
      expect(b.last.amount.minorUnits, 7);
    });

    test('неделя через год: 29.12.2025-04.01.2026, 7 корзин по порядку', () {
      final p = currentPeriod(PeriodKind.week, DateOnly(2026, 1, 1));
      expect(p.range.start, DateOnly(2025, 12, 29));
      expect(p.range.end, DateOnly(2026, 1, 4));
      final b = _totals([
        _tx(DateOnly(2025, 12, 31), 3),
        _tx(DateOnly(2026, 1, 1), 5),
      ], p);
      expect(b, hasLength(7));
      expect(b[2].amount.minorUnits, 3);
      expect(b[3].range, dayRange(DateOnly(2026, 1, 1)));
      expect(b[3].amount.minorUnits, 5);
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

    test('операция с будущей датой есть в столбике, но не в среднем', () {
      final b = _totals([
        _tx(DateOnly(2026, 10, 1), 1100),
        _tx(DateOnly(2026, 10, 20), 5000), // позже «сегодня» (11 октября)
      ], october);
      expect(b[19].amount.minorUnits, 5000);
      expect(bucketAverage(b, today), Money.fromMinor(100, 'RUB')); // 1100/11
    });

    test('год с данными с августа: делит на 3 (август-октябрь)', () {
      final b = _totals([
        _tx(DateOnly(2026, 8, 10), 3000),
        _tx(DateOnly(2026, 10, 3), 600),
      ], currentPeriod(PeriodKind.year, today));
      expect(bucketAverage(b, today), Money.fromMinor(1200, 'RUB')); // 3600/3
    });

    test('пустые дни в начале месяца не учитываются', () {
      final b = _totals([_tx(DateOnly(2026, 10, 8), 400)], october);
      expect(bucketAverage(b, today), Money.fromMinor(100, 'RUB')); // 8-11: /4
    });

    test('нули после первой операции учитываются', () {
      final b = _totals([
        _tx(DateOnly(2026, 10, 3), 500),
        _tx(DateOnly(2026, 10, 7), 500),
      ], october);
      expect(bucketAverage(b, today), Money.fromMinor(111, 'RUB')); // 1000/9
    });

    test('прошедший период тоже считается с первой ненулевой', () {
      final b = _totals([
        _tx(DateOnly(2026, 9, 21), 1000),
      ], currentPeriod(PeriodKind.month, DateOnly(2026, 9, 5)));
      expect(
        bucketAverage(b, today),
        Money.fromMinor(100, 'RUB'),
      ); // 21-30: /10
    });

    test('первая операция в будущей корзине — null', () {
      final b = _totals([_tx(DateOnly(2026, 10, 20), 500)], october);
      expect(bucketAverage(b, today), isNull);
    });

    test('все корзины нулевые — null', () {
      expect(bucketAverage(_totals([], october), today), isNull);
    });

    test('нет корзин — null', () {
      expect(bucketAverage([], today), isNull);
      final d = _totals([], currentPeriod(PeriodKind.day, today));
      expect(bucketAverage(d, today), isNull);
    });
  });

  group('firstFutureBucket (И5, шаг 8.45)', () {
    List<Bucket> month(DateOnly day) => bucketTotals(
      const [],
      currentPeriod(PeriodKind.month, day),
      type: TransactionType.expense,
      currency: 'RUB',
    );

    test('14 октября: будущие — с 15-го, их 17', () {
      final buckets = month(DateOnly(2026, 10, 1));
      final today = DateOnly(2026, 10, 14);
      final from = firstFutureBucket(buckets, today);
      expect(from, 14);
      expect(buckets.length - from, 17);
      expect(buckets[from].range.start, DateOnly(2026, 10, 15));
    });

    test('прошлый месяц — будущих нет', () {
      final buckets = month(DateOnly(2026, 9, 1));
      expect(
        firstFutureBucket(buckets, DateOnly(2026, 10, 14)),
        buckets.length,
      );
    });

    test('последний день месяца — будущих нет, первый — все кроме него', () {
      final buckets = month(DateOnly(2026, 10, 1));
      expect(firstFutureBucket(buckets, DateOnly(2026, 10, 31)), 31);
      expect(firstFutureBucket(buckets, DateOnly(2026, 10, 1)), 1);
    });

    test('год: будущие месяцы', () {
      final buckets = bucketTotals(
        const [],
        currentPeriod(PeriodKind.year, DateOnly(2026, 10, 14)),
        type: TransactionType.expense,
        currency: 'RUB',
      );
      expect(firstFutureBucket(buckets, DateOnly(2026, 10, 14)), 10);
    });

    test('пусто — 0', () {
      expect(firstFutureBucket(const [], DateOnly(2026, 10, 14)), 0);
    });
  });
}
