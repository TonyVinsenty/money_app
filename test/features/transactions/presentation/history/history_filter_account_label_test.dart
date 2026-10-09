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
      accountFilter: const OneAccount('a'),
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

  test('«Без счёта» - один и вместе с другими', () {
    expect(
      historyFilterLabel(
        HistoryFilter(accountFilter: const NoAccount()),
        _cats,
      ),
      'Фильтр: Без счёта',
    );
    final filter = HistoryFilter(
      type: HistoryTypeFilter.expense,
      expenseCategoryIds: {'cafe'},
      accountFilter: const NoAccount(),
    );
    expect(
      historyFilterLabel(filter, _cats),
      'Фильтр: Расходы · Кафе · Без счёта',
    );
    expect(
      historyFilterSpoken(filter, _cats),
      'Фильтр, включён: расходы, Кафе, Без счёта',
    );
    expect(
      historyFilterSpoken(
        HistoryFilter(accountFilter: const NoAccount()),
        _cats,
      ),
      'Фильтр, включён: без счёта',
    );
  });

  test('фильтр без счёта подписан как раньше', () {
    expect(
      historyFilterLabel(HistoryFilter.expenseCategories({'cafe'}), _cats),
      'Фильтр: Расходы · Кафе',
    );
  });
}
