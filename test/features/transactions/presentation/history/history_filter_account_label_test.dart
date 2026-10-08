import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/history_view.dart';
import 'package:money_app/features/transactions/presentation/history/history_filter_label.dart';

final _cats = [
  Category(
    id: 'cafe',
    kind: CategoryKind.expense,
    name: 'Кафе',
    iconKey: 'icon',
    parentId: null,
    sortOrder: 0,
  ),
];

void main() {
  test('только счёт', () {
    expect(
      historyFilterLabel(
        HistoryFilter.account('a'),
        _cats,
        accountName: 'Карта',
      ),
      'Фильтр: Счёт: Карта',
    );
  });

  test('счёт вместе с типом и категорией', () {
    final filter = HistoryFilter(
      type: HistoryTypeFilter.expense,
      expenseCategoryIds: {'cafe'},
      accountId: 'a',
    );
    expect(
      historyFilterLabel(filter, _cats, accountName: 'Карта'),
      'Фильтр: Расходы · Кафе · Счёт: Карта',
    );
    expect(
      historyFilterSpoken(filter, _cats, accountName: 'Карта'),
      'Фильтр, включён: расходы, Кафе, Счёт: Карта',
    );
  });

  test('имя счёта неизвестно - запасной текст', () {
    expect(
      historyFilterLabel(HistoryFilter.account('gone'), _cats),
      'Фильтр: Счёт: $historyUnknownAccount',
    );
  });

  test('фильтр без счёта подписан как раньше', () {
    expect(
      historyFilterLabel(HistoryFilter.expenseCategories({'cafe'}), _cats),
      'Фильтр: Расходы · Кафе',
    );
  });
}
