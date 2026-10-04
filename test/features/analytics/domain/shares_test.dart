import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/category_totals.dart';
import 'package:money_app/features/analytics/domain/shares.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/fixture_transactions.dart';

final _september = DateRange(DateOnly(2026, 9, 1), DateOnly(2026, 9, 30));

/// Суммы в рублях из целых копеек.
List<Money> _amounts(List<int> minorUnits) => [
  for (final m in minorUnits) Money.fromMinor(m, 'RUB'),
];

/// Итог категории для chartSlices: id и сумма в копейках.
CategoryTotal _total(String id, int minorUnits) => CategoryTotal(
  categoryId: id,
  amount: Money.fromMinor(minorUnits, 'RUB'),
  count: 1,
);

/// Проценты одной строкой, для сравнения в тестах.
List<int?> _percents(List<PercentShare> shares) => [
  for (final s in shares) s.percent,
];

int _sum(Iterable<int?> values) => values.fold(0, (a, v) => a + (v ?? 0));

void main() {
  group('percentShares: метод наибольшего остатка', () {
    test('три равные суммы дают 34/33/33, а не 33/33/33', () {
      final shares = percentShares(_amounts([1, 1, 1]));

      expect(_percents(shares), [34, 33, 33]);
    });

    test('сумма процентов ровно 100 на наборе из 10 категорий', () {
      final shares = percentShares(
        _amounts([1234, 987, 650, 540, 430, 321, 210, 150, 80, 12]),
      );

      expect(_sum(_percents(shares)), 100);
    });

    test(
      'сумма процентов ровно 100 на случайных наборах (фиксированное зерно)',
      () {
        final random = Random(20260904);
        for (var set = 0; set < 60; set++) {
          final count = 1 + random.nextInt(15);
          final minors = [
            for (var i = 0; i < count; i++) random.nextInt(1000000),
          ];
          final total = minors.fold(0, (a, b) => a + b);
          final shares = percentShares(_amounts(minors));

          if (total == 0) {
            expect(_percents(shares), everyElement(isNull), reason: '$minors');
          } else {
            expect(_sum(_percents(shares)), 100, reason: '$minors');
          }
        }
      },
    );

    test('ненулевая доля, округлённая до нуля, помечается isBelowOne', () {
      // 4 из 1000 — 0,4 %. Целая часть 0, но сумма больше нуля.
      final shares = percentShares(_amounts([996, 4]));

      expect(_percents(shares), [100, 0]);
      expect(shares[0].isBelowOne, isFalse);
      expect(shares[1].isBelowOne, isTrue);
    });

    test('нулевая сумма не помечается isBelowOne, даже если процент 0', () {
      final shares = percentShares(_amounts([1000, 0]));

      expect(_percents(shares), [100, 0]);
      expect(shares[1].isBelowOne, isFalse);
    });

    test('одна категория получает 100', () {
      expect(_percents(percentShares(_amounts([777]))), [100]);
    });

    test('итог 0 — процентов нет, строки остаются', () {
      final shares = percentShares(_amounts([0, 0]));

      expect(_percents(shares), [null, null]);
      expect(shares.every((s) => !s.isBelowOne), isTrue);
    });

    test('пустой список — пустой результат, без деления на ноль', () {
      expect(percentShares(const []), isEmpty);
    });

    test('суммы около 10^14 копеек не переполняются', () {
      // 10^14 копеек — тысяча миллиардов рублей; ×100 не выходит за int.
      final shares = percentShares(_amounts([100000000000000, 3]));

      expect(_percents(shares), [100, 0]);
      expect(shares[1].isBelowOne, isTrue);
    });

    test('разные валюты — ArgumentError', () {
      expect(
        () => percentShares([
          Money.fromMinor(100, 'RUB'),
          Money.fromMinor(100, 'USD'),
        ]),
        throwsArgumentError,
      );
    });

    test('отрицательная сумма — ArgumentError', () {
      expect(() => percentShares(_amounts([100, -1])), throwsArgumentError);
    });

    test('тестовый набор за сентябрь: проценты категорий в сумме 100', () {
      final totals = totalsByCategory(
        loadFixtureTransactions(),
        _september,
        type: TransactionType.expense,
        currency: 'RUB',
      );
      final shares = percentShares([for (final t in totals) t.amount]);

      expect(_sum(_percents(shares)), 100);
    });
  });

  group('chartSlices: сектора и «Остальное»', () {
    test(
      'две мелкие категории уходят в «Остальное», их проценты складываются',
      () {
        // Итог 10 000. Мелкие: 0,4 % и 0,2 % (порог 3 %).
        final slices = chartSlices([
          _total('cat-a', 5000),
          _total('cat-b', 4000),
          _total('cat-e', 940),
          _total('cat-c', 40),
          _total('cat-d', 20),
        ]);

        expect(slices.map((s) => s.categoryIds), [
          ['cat-a'],
          ['cat-b'],
          ['cat-e'],
          ['cat-c', 'cat-d'],
        ]);
        expect(slices.map((s) => s.isOther), [false, false, false, true]);
        expect(_percents([for (final s in slices) s.share]), [50, 40, 10, 0]);
        final other = slices.last;
        expect(other.amount, Money.fromMinor(60, 'RUB'));
        expect(other.share.isBelowOne, isTrue);
      },
    );

    test('одна мелкая категория остаётся своим сектором', () {
      // Итог 10 000; 0,4 % — единственная мелкая.
      final slices = chartSlices([
        _total('cat-a', 5000),
        _total('cat-b', 4960),
        _total('cat-c', 40),
      ]);

      expect(slices, hasLength(3));
      expect(slices.every((s) => !s.isOther), isTrue);
      final small = slices.last;
      expect(small.categoryIds, ['cat-c']);
      expect(small.share.percent, 0);
      expect(small.share.isBelowOne, isTrue);
    });

    test('ровно 3 % не мелкая, чуть меньше — мелкая', () {
      // Итог 10 000: 7000, 2151, 300 (ровно 3 %), 299 (2,99 %), 250 (2,5 %).
      final slices = chartSlices([
        _total('cat-a', 7000),
        _total('cat-w', 2151),
        _total('cat-x', 300),
        _total('cat-z', 299),
        _total('cat-y', 250),
      ]);

      expect(slices.map((s) => s.categoryIds), [
        ['cat-a'],
        ['cat-w'],
        ['cat-x'],
        ['cat-z', 'cat-y'],
      ]);
      expect(_percents([for (final s in slices) s.share]), [70, 22, 3, 5]);
    });

    test('сектора больше 8 — лишние уходят в «Остальное»', () {
      // 12 категорий по 1000 из 12 000: каждая по 8,33 %, все крупные.
      final slices = chartSlices([
        for (var i = 1; i <= 12; i++)
          _total('cat-${i.toString().padLeft(2, '0')}', 1000),
      ]);

      final named = slices.where((s) => !s.isOther).toList();
      final other = slices.singleWhere((s) => s.isOther);
      expect(named, hasLength(maxNamedSlices));
      expect(_percents([for (final s in named) s.share]), [
        9,
        9,
        9,
        9,
        8,
        8,
        8,
        8,
      ]);
      expect(other.categoryIds, ['cat-09', 'cat-10', 'cat-11', 'cat-12']);
      expect(other.amount, Money.fromMinor(4000, 'RUB'));
      expect(other.share.percent, 32);
      expect(_sum(_percents([for (final s in slices) s.share])), 100);
    });

    test('одна категория — один сектор на 100 %', () {
      final slices = chartSlices([_total('cat-a', 1234)]);

      expect(slices, hasLength(1));
      expect(slices.single.isOther, isFalse);
      expect(slices.single.share.percent, 100);
    });

    test('пустой список и итог 0 — пустой результат', () {
      expect(chartSlices(const []), isEmpty);
      expect(chartSlices([_total('cat-a', 0)]), isEmpty);
    });

    test('тестовый набор за сентябрь: сектора в сумме дают итог и 100 %', () {
      final totals = totalsByCategory(
        loadFixtureTransactions(),
        _september,
        type: TransactionType.expense,
        currency: 'RUB',
      );
      final slices = chartSlices(totals);

      final amount = slices.fold(Money.zero('RUB'), (a, s) => a + s.amount);
      expect(amount, Money.fromMinor(12803388, 'RUB'));
      expect(_sum(_percents([for (final s in slices) s.share])), 100);
      final ids = [for (final s in slices) ...s.categoryIds];
      expect(ids.toSet(), totals.map((t) => t.categoryId).toSet());
    });
  });

  test('в файле расчёта долей нет типа double (деньги только целые)', () {
    final source = File('lib/features/analytics/domain/shares.dart')
        .readAsStringSync();

    expect(source, isNot(contains('double')));
  });
}
