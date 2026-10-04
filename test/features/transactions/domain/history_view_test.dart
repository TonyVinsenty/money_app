import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/category_totals.dart';
import 'package:money_app/features/transactions/domain/history_view.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/fixture_transactions.dart';

Transaction _tx(
  String id,
  TransactionType type,
  int minor, {
  DateOnly? day,
  int hour = 12,
  String categoryId = 'cat-a',
  String? subcategoryId,
  String currency = 'RUB',
}) {
  final d = day ?? DateOnly(2026, 9, 10);
  return Transaction(
    id: id,
    type: type,
    amount: Money.fromMinor(minor, currency),
    occurredOn: d,
    occurredAt: DateTime.utc(d.year, d.month, d.day, hour),
    categoryId: categoryId,
    subcategoryId: subcategoryId,
  );
}

List<String> _ids(List<Transaction> list) => [for (final t in list) t.id];

const _expense = TransactionType.expense;
const _income = TransactionType.income;

void main() {
  group('HistoryFilter', () {
    test('off не активен, любой тип или набор включает фильтр', () {
      expect(HistoryFilter.off.isActive, isFalse);
      expect(
        const HistoryFilter(type: HistoryTypeFilter.income).isActive,
        isTrue,
      );
      expect(const HistoryFilter(expenseCategoryIds: {}).isActive, isTrue);
      expect(const HistoryFilter(incomeCategoryIds: {'x'}).isActive, isTrue);
      expect(
        const HistoryFilter.expenseCategories({'a'}).type,
        HistoryTypeFilter.expense,
      );
    });

    test('равенство сравнивает наборы по содержимому, null != пустой', () {
      expect(
        const HistoryFilter(expenseCategoryIds: {'a', 'b'}),
        HistoryFilter(expenseCategoryIds: {'b', 'a'}),
      );
      expect(
        const HistoryFilter(expenseCategoryIds: {'a', 'b'}).hashCode,
        HistoryFilter(expenseCategoryIds: {'b', 'a'}).hashCode,
      );
      expect(
        const HistoryFilter(expenseCategoryIds: {}),
        isNot(HistoryFilter.off),
      );
      expect(
        const HistoryFilter(expenseCategoryIds: {'a'}),
        isNot(const HistoryFilter(incomeCategoryIds: {'a'})),
      );
    });
  });

  group('applyHistoryView: фильтр', () {
    final list = [
      _tx('e1', _expense, 100, categoryId: 'food'),
      _tx('e2', _expense, 200, categoryId: 'cafe'),
      _tx('e3', _expense, 300, categoryId: 'food', subcategoryId: 'veg'),
      _tx('i1', _income, 400, categoryId: 'salary'),
      _tx('i2', _income, 500, categoryId: 'gift'),
    ];
    Set<String> run(HistoryFilter f) =>
        _ids(applyHistoryView(list, f, HistorySort.oldestFirst)).toSet();

    test('каждый тип', () {
      expect(run(HistoryFilter.off), {'e1', 'e2', 'e3', 'i1', 'i2'});
      expect(run(const HistoryFilter(type: HistoryTypeFilter.income)), {
        'i1',
        'i2',
      });
      expect(run(const HistoryFilter(type: HistoryTypeFilter.expense)), {
        'e1',
        'e2',
        'e3',
      });
    });

    test('null — все категории вида, пустой набор — ни одной', () {
      expect(run(const HistoryFilter(expenseCategoryIds: {})), {'i1', 'i2'});
      expect(
        run(
          const HistoryFilter(
            type: HistoryTypeFilter.expense,
            expenseCategoryIds: {},
          ),
        ),
        isEmpty,
      );
    });

    test('«Расходы · Продукты» с типом «Все» = эти расходы + все доходы', () {
      expect(run(const HistoryFilter(expenseCategoryIds: {'food'})), {
        'e1',
        'e3',
        'i1',
        'i2',
      });
      expect(run(const HistoryFilter(incomeCategoryIds: {'gift'})), {
        'e1',
        'e2',
        'e3',
        'i2',
      });
    });

    test('операция с подкатегорией проходит по своей категории', () {
      expect(run(const HistoryFilter.expenseCategories({'food'})), {
        'e1',
        'e3',
      });
      expect(run(const HistoryFilter.expenseCategories({'veg'})), isEmpty);
    });
  });

  group('applyHistoryView: сортировка', () {
    test('по дате в обе стороны: день, момент, id', () {
      final list = [
        _tx('b', _expense, 1, day: DateOnly(2026, 9, 5), hour: 10),
        _tx('a', _expense, 1, day: DateOnly(2026, 9, 5), hour: 10),
        _tx('c', _expense, 1, day: DateOnly(2026, 9, 5), hour: 15),
        _tx('d', _expense, 1, day: DateOnly(2026, 9, 6), hour: 1),
        _tx('e', _expense, 1, day: DateOnly(2026, 9, 4), hour: 23),
      ];
      expect(
        _ids(
          applyHistoryView(list, HistoryFilter.off, HistorySort.oldestFirst),
        ),
        ['e', 'a', 'b', 'c', 'd'],
      );
      expect(
        _ids(
          applyHistoryView(list, HistoryFilter.off, HistorySort.newestFirst),
        ),
        ['d', 'c', 'b', 'a', 'e'],
      );
    });

    test('по сумме в обе стороны; при равных суммах новее выше, затем id', () {
      final list = [
        _tx('a', _expense, 500, day: DateOnly(2026, 9, 1)),
        _tx('b', _expense, 500, day: DateOnly(2026, 9, 3), hour: 8),
        _tx('c', _expense, 500, day: DateOnly(2026, 9, 3), hour: 8),
        _tx('d', _expense, 500, day: DateOnly(2026, 9, 3), hour: 9),
        _tx('s', _expense, 100),
        _tx('l', _expense, 900),
      ];
      expect(
        _ids(
          applyHistoryView(list, HistoryFilter.off, HistorySort.largestFirst),
        ),
        ['l', 'd', 'b', 'c', 'a', 's'],
      );
      expect(
        _ids(
          applyHistoryView(list, HistoryFilter.off, HistorySort.smallestFirst),
        ),
        ['s', 'd', 'b', 'c', 'a', 'l'],
      );
    });

    test('входной список не меняется', () {
      final list = [_tx('a', _expense, 1), _tx('b', _income, 2)];
      final before = List.of(list);
      final result = applyHistoryView(
        list,
        const HistoryFilter(type: HistoryTypeFilter.income),
        HistorySort.largestFirst,
      );
      expect(list, before);
      expect(identical(result, list), isFalse);
    });

    test('разные валюты при сортировке по сумме — ArgumentError', () {
      final list = [
        _tx('a', _expense, 1),
        _tx('b', _expense, 2, currency: 'USD'),
      ];
      expect(
        () =>
            applyHistoryView(list, HistoryFilter.off, HistorySort.largestFirst),
        throwsArgumentError,
      );
      expect(
        () =>
            applyHistoryView(list, HistoryFilter.off, HistorySort.newestFirst),
        returnsNormally,
      );
    });
  });

  test(
    'тестовый набор: сентябрь, расходы «Продуктов» = итог totalsByCategory',
    () {
      final all = loadFixtureTransactions();
      final september = DateRange(DateOnly(2026, 9, 1), DateOnly(2026, 9, 30));
      final inSeptember = all.where((t) => september.contains(t.occurredOn));

      final shown = applyHistoryView(
        inSeptember,
        const HistoryFilter.expenseCategories({'cat-food'}),
        HistorySort.largestFirst,
      );
      final sum = shown.fold(Money.zero('RUB'), (a, t) => a + t.amount);
      final food = totalsByCategory(
        all,
        september,
        type: _expense,
        currency: 'RUB',
      ).singleWhere((t) => t.categoryId == 'cat-food');

      expect(sum, food.amount);
      expect(shown.length, food.count);
      expect(shown.every((t) => t.type == _expense), isTrue);
    },
  );
}
