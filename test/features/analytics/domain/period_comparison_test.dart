import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/period_comparison.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/fixture_transactions.dart';

final _cur = DateRange(DateOnly(2026, 10, 1), DateOnly(2026, 10, 31));
final _prev = DateRange(DateOnly(2026, 9, 1), DateOnly(2026, 9, 30));
final _oct = DateOnly(2026, 10, 5);
final _sep = DateOnly(2026, 9, 5);

Transaction _tx(
  int minor,
  DateOnly day, {
  String cat = 'a',
  String? sub,
  TransactionType type = TransactionType.expense,
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

List<CategoryComparison> _compare(
  List<Transaction> list, {
  TransactionType type = TransactionType.expense,
}) => compareByCategory(list, _cur, _prev, type: type, currency: 'RUB');

void main() {
  group('percentChange', () {
    test('округление половины от нуля', () {
      expect(percentChange(9, 8), 13); // +12,5 %
      expect(percentChange(7, 8), -13); // -12,5 %
    });

    test('без изменений и обычные значения', () {
      expect(percentChange(100, 100), 0);
      expect(percentChange(150, 100), 50);
      expect(percentChange(0, 100), -100);
      expect(percentChange(1, 3), -67);
      expect(percentChange(201, 100), 101);
    });

    test('прошлое 0 -> null, в том числе 0 и 0', () {
      expect(percentChange(5, 0), isNull);
      expect(percentChange(0, 0), isNull);
    });

    test('большие суммы без переполнения', () {
      const big = 100000000000000; // 10^14
      expect(percentChange(big * 2, big), 100);
    });

    test('отрицательные суммы -> ArgumentError', () {
      expect(() => percentChange(-1, 5), throwsArgumentError);
      expect(() => percentChange(1, -5), throwsArgumentError);
    });
  });

  group('compareByCategory', () {
    test('порядок: по «сейчас», затем исчезнувшие; ничья по id', () {
      final rows = _compare([
        _tx(100, _oct, cat: 'b'),
        _tx(100, _oct, cat: 'a'),
        _tx(500, _oct, cat: 'c'),
        _tx(300, _sep, cat: 'gone-small'),
        _tx(900, _sep, cat: 'gone-big'),
        _tx(50, _sep, cat: 'c'),
      ]);
      expect(rows.map((r) => r.categoryId), [
        'c',
        'a',
        'b',
        'gone-big',
        'gone-small',
      ]);
      final c = rows.first;
      expect(c.current.minorUnits, 500);
      expect(c.previous.minorUnits, 50);
      expect(c.difference.minorUnits, 450);
      expect(c.percent, 900);
    });

    test('исчезнувшая -100 %, новая без процента', () {
      final rows = _compare([_tx(200, _sep, cat: 'old'), _tx(70, _oct)]);
      final old = rows.singleWhere((r) => r.categoryId == 'old');
      expect(old.percent, -100);
      expect(old.difference.minorUnits, -200);
      expect(rows.singleWhere((r) => r.categoryId == 'a').percent, isNull);
    });

    test('доходы и расходы раздельно', () {
      final list = [
        _tx(100, _oct, cat: 'x'),
        _tx(400, _oct, cat: 'y', type: TransactionType.income),
      ];
      expect(_compare(list).map((r) => r.categoryId), ['x']);
      expect(
        _compare(list, type: TransactionType.income).map((r) => r.categoryId),
        ['y'],
      );
    });

    test('подкатегории сводятся к категории', () {
      final rows = _compare([
        _tx(100, _oct, sub: 's1'),
        _tx(200, _oct, sub: 's2'),
        _tx(50, _oct),
      ]);
      expect(rows, hasLength(1));
      expect(rows.single.current.minorUnits, 350);
    });

    test('чужая валюта -> ArgumentError', () {
      expect(
        () => _compare([_tx(100, _oct), _tx(100, _oct, currency: 'USD')]),
        throwsArgumentError,
      );
    });

    test('пусто -> пустой список', () {
      expect(_compare([]), isEmpty);
    });
  });

  group('comparePeriodTotals', () {
    test('расходы и доходы', () {
      final list = [
        _tx(100, _oct),
        _tx(300, _sep),
        _tx(900, _oct, type: TransactionType.income),
      ];
      final exp = comparePeriodTotals(
        list,
        _cur,
        _prev,
        type: TransactionType.expense,
        currency: 'RUB',
      );
      expect(exp.difference.minorUnits, -200);
      expect(exp.percent, -67);
      final inc = comparePeriodTotals(
        list,
        _cur,
        _prev,
        type: TransactionType.income,
        currency: 'RUB',
      );
      expect(inc.current.minorUnits, 900);
      expect(inc.percent, isNull);
    });
  });

  group('на тестовом наборе', () {
    final all = loadFixtureTransactions();
    final august = DateRange(DateOnly(2026, 8, 1), DateOnly(2026, 8, 31));
    final september = DateRange(DateOnly(2026, 9, 1), DateOnly(2026, 9, 30));

    test('сентябрь против пустого августа: проценты null, сумма = итог', () {
      final rows = compareByCategory(
        all,
        september,
        august,
        type: TransactionType.expense,
        currency: 'RUB',
      );
      expect(rows, isNotEmpty);
      expect(rows.every((r) => r.percent == null), isTrue);
      expect(rows.every((r) => r.previous.isZero), isTrue);
      final total = comparePeriodTotals(
        all,
        september,
        august,
        type: TransactionType.expense,
        currency: 'RUB',
      );
      final sum = rows.fold(Money.zero('RUB'), (s, r) => s + r.current);
      expect(sum, total.current);
      expect(total.percent, isNull);
    });
  });
}
