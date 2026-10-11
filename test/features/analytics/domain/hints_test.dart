import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/domain/hints.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

// 2026-10-11 - воскресенье. Окно октября: 1.09-11.10; сравнение: 1-11.09.
final _today = DateOnly(2026, 10, 11);
final _october = currentPeriod(PeriodKind.month, _today);

var _seq = 0;

Transaction _tx(
  int minor,
  DateOnly day, {
  String category = 'cat',
  String currency = 'RUB',
  TransactionType type = TransactionType.expense,
}) {
  _seq++;
  return Transaction(
    id: 't${_seq.toString().padLeft(4, '0')}',
    type: type,
    amount: Money.fromMinor(minor, currency),
    occurredOn: day,
    occurredAt: DateTime.utc(day.year, day.month, day.day, 12),
    categoryId: category,
  );
}

DateOnly _sep(int d) => DateOnly(2026, 9, d);
DateOnly _oct(int d) => DateOnly(2026, 10, d);

List<AnalyticsHint> _hints(
  List<Transaction> all, {
  AnalyticsPeriod? period,
  String currency = 'RUB',
  int? digits,
}) => analyticsHints(
  all,
  period ?? _october,
  _today,
  currency: currency,
  currencyDigits: digits,
);

String _d(AnalyticsHint h) => switch (h) {
  CategoryAbovePreviousHint() =>
    'above ${h.categoryId} ${h.current.minorUnits}/${h.previousTotal.minorUnits}',
  AverageCheckChangeHint() =>
    'avg ${h.categoryId} ${h.currentAverage.minorUnits}/'
        '${h.previousAverage.minorUnits} ${h.percent}',
  BusiestWeekdayHint() =>
    'day ${h.weekday} ${h.sharePercent}% '
        '${h.amount.minorUnits}',
};

List<String> _describe(List<AnalyticsHint> list) => list.map(_d).toList();

/// Пять операций категории [c] по [each] минорных единиц в окне [days].
List<Transaction> _five(String c, int each, DateOnly Function(int) day) => [
  for (var i = 1; i <= 5; i++) _tx(each, day(i), category: c),
];

void main() {
  group('rule 1: category above the whole previous period', () {
    // Прошлый период целиком (сентябрь), хотя сравнение - только 1-11.09.
    List<Transaction> data(int now, {int before = 100000}) => [
      _tx(before, _sep(20), category: 'cafe'),
      _tx(now, _oct(10), category: 'cafe'),
    ];

    test('previous at threshold, current just above: hint', () {
      final hints = _hints(data(100001));
      expect(_describe(hints).first, 'above cafe 100001/100000');
    });

    test('current equal to previous: no hint (strictly greater)', () {
      expect(
        _describe(_hints(data(100000))).where((s) => s.startsWith('above')),
        isEmpty,
      );
    });

    test('previous just below threshold: no hint', () {
      final hints = _hints(data(500000, before: 99999));
      expect(hints.whereType<CategoryAbovePreviousHint>(), isEmpty);
    });

    test('threshold follows currency digits (JPY 0, custom 3)', () {
      List<Transaction> jpy(int before) => [
        _tx(before, _sep(20), category: 'a', currency: 'JPY'),
        _tx(before + 1, _oct(10), category: 'a', currency: 'JPY'),
      ];
      expect(
        _hints(
          jpy(1000),
          currency: 'JPY',
        ).whereType<CategoryAbovePreviousHint>(),
        hasLength(1),
      );
      expect(
        _hints(
          jpy(999),
          currency: 'JPY',
        ).whereType<CategoryAbovePreviousHint>(),
        isEmpty,
      );
      List<Transaction> xyz(int before) => [
        _tx(before, _sep(20), category: 'a', currency: 'XYZ'),
        _tx(before + 1, _oct(10), category: 'a', currency: 'XYZ'),
      ];
      expect(
        _hints(
          xyz(1000000),
          currency: 'XYZ',
          digits: 3,
        ).whereType<CategoryAbovePreviousHint>(),
        hasLength(1),
      );
      expect(
        _hints(
          xyz(999999),
          currency: 'XYZ',
          digits: 3,
        ).whereType<CategoryAbovePreviousHint>(),
        isEmpty,
      );
    });

    test('complete past period is compared with the whole one before it', () {
      final september = currentPeriod(PeriodKind.month, _sep(15));
      final hints = _hints([
        _tx(100000, DateOnly(2026, 8, 5), category: 'cafe'),
        _tx(100001, _sep(5), category: 'cafe'),
      ], period: september);
      expect(_describe(hints).first, 'above cafe 100001/100000');
    });

    test('income of the category is ignored', () {
      final hints = _hints([
        ..._hintsDataExpenseOnly(),
        _tx(900000, _oct(9), category: 'cafe', type: TransactionType.income),
      ]);
      expect(hints.whereType<CategoryAbovePreviousHint>(), isEmpty);
    });
  });

  group('rule 2: average check change', () {
    List<Transaction> data(int now, {int before = 1000, int nowCount = 5}) => [
      ..._five('prod', before, _sep),
      for (var i = 1; i <= nowCount; i++) _tx(now, _oct(i), category: 'prod'),
    ];

    test('+15 % exactly: hint with signed percent', () {
      expect(_describe(_hints(data(1150))), ['avg prod 1150/1000 15']);
    });

    test('+14 %: no hint', () {
      expect(_hints(data(1144)), isEmpty);
    });

    test('-15 % exactly: hint, -14 %: none', () {
      expect(_describe(_hints(data(850))), ['avg prod 850/1000 -15']);
      expect(_hints(data(856)), isEmpty);
    });

    test('5 operations in both periods needed: 4 now or 4 before - none', () {
      expect(_hints(data(1150, nowCount: 4)), isEmpty);
      final fewBefore = [
        for (var i = 1; i <= 4; i++) _tx(1000, _sep(i), category: 'prod'),
        for (var i = 1; i <= 5; i++) _tx(1150, _oct(i), category: 'prod'),
      ];
      expect(_hints(fewBefore), isEmpty);
    });

    test('sorted by current category sum, then id', () {
      final hints = _hints([
        ..._five('a', 1000, _sep),
        ..._five('a', 1200, _oct),
        ..._five('b', 1000, _sep),
        ..._five('b', 2000, _oct),
        ..._five('c', 1000, _sep),
        ..._five('c', 1200, _oct),
      ]);
      expect(_describe(hints), [
        'avg b 2000/1000 100',
        'avg a 1200/1000 20',
        'avg c 1200/1000 20',
      ]);
    });
  });

  group('rule 3: busiest weekday', () {
    // Суббота 10.10 - 100; Пн-Чт 14-17.09 - по 75 (итого 400, доля 25 %).
    List<Transaction> data({int thu = 75, int firstDay = 14}) => [
      _tx(100, _oct(10), category: 's'),
      _tx(75, _sep(firstDay), category: 'm'),
      _tx(75, _sep(firstDay + 1), category: 't'),
      _tx(75, _sep(firstDay + 2), category: 'w'),
      _tx(thu, _sep(firstDay + 3), category: 'h'),
    ];

    test('exactly 25 % and exactly 28 days of data: hint', () {
      expect(_describe(_hints(data())), ['day 6 25% 100']);
    });

    test('24.9 % (total 401): no hint', () {
      expect(_hints(data(thu: 76)), isEmpty);
    });

    test('27 days of data: no hint (first expense 15.09)', () {
      expect(_hints(data(firstDay: 15)), isEmpty);
    });

    test('equal sums: earlier weekday wins', () {
      final hints = _hints([
        _tx(100, _sep(14), category: 'a'), // понедельник
        _tx(100, _oct(10), category: 'b'), // суббота
        _tx(1, _sep(15), category: 'c'),
      ]);
      expect(_describe(hints), ['day 1 50% 100']);
    });

    test('short period (week) never has 28 days of data', () {
      final week = currentPeriod(PeriodKind.week, _today);
      expect(_hints(data(), period: week), isEmpty);
    });

    test('income is ignored', () {
      final hints = _hints([
        ...data(thu: 76),
        _tx(9999, _oct(10), category: 'x', type: TransactionType.income),
      ]);
      expect(hints, isEmpty);
    });
  });

  group('weekdayTotals', () {
    final range = DateRange(_sep(1), _oct(11));

    test('Monday first, expenses only, inside the range', () {
      final totals = weekdayTotals(
        [
          _tx(10, _sep(14)), // понедельник
          _tx(5, _sep(21)), // понедельник
          _tx(7, _oct(11)), // воскресенье
          _tx(100, _sep(15), type: TransactionType.income),
          _tx(100, DateOnly(2026, 8, 31)), // вне диапазона
        ],
        range,
        currency: 'RUB',
      );
      expect([for (final m in totals) m.minorUnits], [15, 0, 0, 0, 0, 0, 7]);
    });

    test('empty input: seven zeros', () {
      final totals = weekdayTotals(const [], range, currency: 'RUB');
      expect(totals, hasLength(7));
      expect(totals.every((m) => m.isZero), isTrue);
    });

    test('foreign currency throws', () {
      expect(
        () => weekdayTotals(
          [_tx(1, _sep(14), currency: 'USD')],
          range,
          currency: 'RUB',
        ),
        throwsArgumentError,
      );
    });
  });

  group('analyticsHints as a whole', () {
    List<Transaction> everything() => [
      _tx(100000, _sep(20), category: 'cafe'),
      _tx(100001, _oct(10), category: 'cafe'),
      ..._five('prod', 1000, _sep),
      ..._five('prod', 1150, _oct),
    ];

    test('no data: empty', () {
      expect(_hints(const []), isEmpty);
    });

    test('order is rule 1, rule 2, rule 3', () {
      final hints = _hints(everything());
      expect(hints.map((h) => h.runtimeType.toString()), [
        'CategoryAbovePreviousHint',
        'AverageCheckChangeHint',
        'BusiestWeekdayHint',
      ]);
    });

    test('no more than 3: extra rule 1 hints cut, sorted by sum', () {
      final hints = _hints([
        for (final (id, now) in [
          ('c1', 100001),
          ('c2', 100004),
          ('c3', 100003),
          ('c4', 100002),
        ]) ...[
          _tx(100000, _sep(20), category: id),
          _tx(now, _oct(10), category: id),
        ],
      ]);
      expect(_describe(hints), [
        'above c2 100004/100000',
        'above c3 100003/100000',
        'above c4 100002/100000',
      ]);
    });

    test('deterministic: any input order gives the same result', () {
      final base = _describe(_hints(everything()));
      final reversed = everything().reversed.toList();
      final rotated = [...everything().skip(4), ...everything().take(4)];
      expect(_describe(_hints(reversed)), base);
      expect(_describe(_hints(rotated)), base);
    });

    test('only expenses: income alone gives no hints', () {
      final hints = _hints([
        for (final t in everything())
          _tx(
            t.amount.minorUnits,
            t.occurredOn,
            category: t.categoryId,
            type: TransactionType.income,
          ),
      ]);
      expect(hints, isEmpty);
    });
  });
}

/// Расходы для проверки доходов: сентябрь 100000 и октябрь 100000 на 'cafe'.
List<Transaction> _hintsDataExpenseOnly() => [
  _tx(100000, _sep(20), category: 'cafe'),
  _tx(100000, _oct(10), category: 'cafe'),
];
