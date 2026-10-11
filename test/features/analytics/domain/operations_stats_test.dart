import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/operations_stats.dart';
import 'package:money_app/features/csv_import/domain/parse_csv_import.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../../tool/make_test_dataset.dart';
import '../../../support/fixed_clock.dart';

final _september = DateRange(DateOnly(2026, 9, 1), DateOnly(2026, 9, 30));
const _expense = TransactionType.expense;

Transaction _tx(
  String id,
  int minor, {
  int day = 10,
  int hour = 12,
  String categoryId = 'cat',
  String? subcategoryId,
  String currency = 'RUB',
  TransactionType type = _expense,
}) {
  return Transaction(
    id: id,
    type: type,
    amount: Money.fromMinor(minor, currency),
    occurredOn: DateOnly(2026, 9, day),
    occurredAt: DateTime.utc(2026, 9, day, hour),
    categoryId: categoryId,
    subcategoryId: subcategoryId,
  );
}

List<String> _ids(List<Transaction> list) => [for (final t in list) t.id];

void main() {
  group('topTransactions', () {
    test('sorts by amount descending and limits to 10', () {
      final all = [for (var i = 1; i <= 12; i++) _tx('t$i', i * 100)];
      final top = topTransactions(all, _september, _expense, currency: 'RUB');
      expect(top, hasLength(10));
      expect(top.first.id, 't12');
      expect(top.last.id, 't3');
    });

    test('fewer than limit returns all', () {
      final top = topTransactions(
        [_tx('a', 100), _tx('b', 300)],
        _september,
        _expense,
        currency: 'RUB',
      );
      expect(_ids(top), ['b', 'a']);
    });

    test('ties: later moment first, then id; input order does not matter', () {
      final a = _tx('a', 500, day: 5);
      final b = _tx('b', 500, day: 7);
      final c = _tx('c', 500, day: 7);
      final d = _tx('d', 500, day: 7, hour: 15);
      for (final input in [
        [a, b, c, d],
        [d, c, b, a],
        [c, a, d, b],
      ]) {
        expect(
          _ids(topTransactions(input, _september, _expense, currency: 'RUB')),
          ['d', 'b', 'c', 'a'],
        );
      }
    });

    test('skips zero, other type and out-of-period operations', () {
      final top = topTransactions(
        [
          _tx('zero', 0),
          _tx('inc', 900, type: TransactionType.income),
          Transaction(
            id: 'aug',
            type: _expense,
            amount: Money.fromMinor(999, 'RUB'),
            occurredOn: DateOnly(2026, 8, 31),
            occurredAt: DateTime.utc(2026, 8, 31, 12),
            categoryId: 'cat',
          ),
          _tx('ok', 100),
        ],
        _september,
        _expense,
        currency: 'RUB',
      );
      expect(_ids(top), ['ok']);
    });

    test('empty input and limit 0', () {
      expect(
        topTransactions([], _september, _expense, currency: 'RUB'),
        isEmpty,
      );
      expect(
        topTransactions(
          [_tx('a', 1)],
          _september,
          _expense,
          currency: 'RUB',
          limit: 0,
        ),
        isEmpty,
      );
    });

    test('other currency throws', () {
      expect(
        () => topTransactions(
          [_tx('a', 1, currency: 'USD')],
          _september,
          _expense,
          currency: 'RUB',
        ),
        throwsArgumentError,
      );
    });
  });

  group('categoryStats', () {
    test('subcategories fold into the parent, zero counted in number', () {
      final stats = categoryStats(
        [
          _tx('1', 1000, categoryId: 'food'),
          _tx('2', 2000, categoryId: 'food', subcategoryId: 'veg'),
          _tx('3', 0, categoryId: 'food', subcategoryId: 'milk'),
          _tx('4', 500, categoryId: 'taxi'),
        ],
        _september,
        _expense,
        currency: 'RUB',
      );
      expect([for (final s in stats) s.categoryId], ['food', 'taxi']);
      expect(stats[0].count, 3);
      expect(stats[0].amount, Money.fromMinor(3000, 'RUB'));
      expect(stats[0].average, Money.fromMinor(1000, 'RUB'));
      expect(stats[1].average, Money.fromMinor(500, 'RUB'));
    });

    test('average rounds half away from zero', () {
      final stats = categoryStats(
        [_tx('1', 1), _tx('2', 2)],
        _september,
        _expense,
        currency: 'RUB',
      );
      expect(stats.single.average, Money.fromMinor(2, 'RUB'));
    });

    test('order: count, then amount, then id', () {
      final stats = categoryStats(
        [
          _tx('1', 100, categoryId: 'b'),
          _tx('2', 100, categoryId: 'b'),
          _tx('3', 900, categoryId: 'a'),
          _tx('4', 50, categoryId: 'c'),
          _tx('5', 50, categoryId: 'c'),
          _tx('6', 5000, categoryId: 'z'),
          _tx('7', 50, categoryId: 'd'),
          _tx('8', 50, categoryId: 'd'),
        ],
        _september,
        _expense,
        currency: 'RUB',
      );
      expect([for (final s in stats) s.categoryId], ['b', 'c', 'd', 'z', 'a']);
    });

    test('most frequent: tie on count goes to larger amount', () {
      final stats = categoryStats(
        [
          _tx('1', 100, categoryId: 'a'),
          _tx('2', 100, categoryId: 'a'),
          _tx('3', 300, categoryId: 'b'),
          _tx('4', 300, categoryId: 'b'),
          _tx('5', 9999, categoryId: 'c'),
        ],
        _september,
        _expense,
        currency: 'RUB',
      );
      expect(mostFrequentCategory(stats)!.categoryId, 'b');
      expect(mostFrequentCategory(stats.reversed.toList())!.categoryId, 'b');
    });

    test('most frequent: full tie goes to smaller id; empty is null', () {
      final stats = categoryStats(
        [_tx('1', 100, categoryId: 'y'), _tx('2', 100, categoryId: 'x')],
        _september,
        _expense,
        currency: 'RUB',
      );
      expect(mostFrequentCategory(stats.reversed.toList())!.categoryId, 'x');
      expect(mostFrequentCategory([]), isNull);
    });

    test('other currency throws', () {
      expect(
        () => categoryStats(
          [_tx('a', 1, currency: 'USD')],
          _september,
          _expense,
          currency: 'RUB',
        ),
        throwsArgumentError,
      );
    });
  });

  group('test dataset', () {
    late List<ParsedCsvRow> rows;
    late List<Transaction> all;

    setUpAll(() {
      final parsed = parseCsvImport(
        File(testDatasetPath).readAsBytesSync(),
        clock: FixedClock(DateTime.utc(2026, 10, 7, 12)),
      );
      rows = (parsed as CsvImportParsed).rows;
      all = [
        for (final row in rows)
          Transaction(
            id: 'row-${row.line}',
            type: row.type,
            amount: row.amount,
            occurredOn: row.day,
            occurredAt: row.occurredAt,
            categoryId: row.categoryName,
            subcategoryId: row.subcategoryName,
          ),
      ];
    });

    for (final (name, range) in [
      ('July', DateRange(DateOnly(2026, 7, 1), DateOnly(2026, 7, 31))),
      ('September', _september),
    ]) {
      test('$name: counts per category match a direct count', () {
        final direct = <String, int>{};
        var total = 0;
        for (final row in rows) {
          if (row.type != _expense || !range.contains(row.day)) continue;
          direct[row.categoryName] = (direct[row.categoryName] ?? 0) + 1;
          total++;
        }
        final stats = categoryStats(all, range, _expense, currency: 'RUB');
        expect({for (final s in stats) s.categoryId: s.count}, direct);
        expect(stats.fold<int>(0, (sum, s) => sum + s.count), total);
        expect(total, name == 'July' ? 146 : 137);

        final top = topTransactions(all, range, _expense, currency: 'RUB');
        expect(top, hasLength(10));
        for (var i = 1; i < top.length; i++) {
          expect(top[i - 1].amount >= top[i].amount, isTrue);
        }
      });
    }
  });
}
