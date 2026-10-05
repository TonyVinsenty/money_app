import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/history_view.dart';
import 'package:money_app/features/transactions/presentation/history/history_filter_label.dart';

Category _c(String id, String name, {bool archived = false}) => Category(
  id: id,
  kind: CategoryKind.expense,
  name: name,
  iconKey: 'icon',
  parentId: null,
  sortOrder: 0,
  archivedAt: archived ? DateTime.utc(2026, 9, 1) : null,
);

final _cats = [
  _c('a', 'Продукты'),
  _c('b', 'Кафе'),
  _c('c', 'Такси'),
  _c('d', 'Дом'),
  _c('e', 'Связь'),
  _c('old', 'Старая', archived: true),
];

void main() {
  test('тип без категорий', () {
    expect(
      historyFilterLabel(
        const HistoryFilter(type: HistoryTypeFilter.income),
        _cats,
      ),
      'Фильтр: Доходы',
    );
    expect(
      historyFilterLabel(
        const HistoryFilter(type: HistoryTypeFilter.expense),
        _cats,
      ),
      'Фильтр: Расходы',
    );
  });

  test('одна и две категории называются по именам', () {
    expect(
      historyFilterLabel(const HistoryFilter.expenseCategories({'a'}), _cats),
      'Фильтр: Расходы · Продукты',
    );
    expect(
      historyFilterLabel(
        const HistoryFilter.expenseCategories({'a', 'b'}),
        _cats,
      ),
      'Фильтр: Расходы · Продукты, Кафе',
    );
  });

  test('три и больше — числом с правильной формой слова', () {
    String label(Set<String> ids) =>
        historyFilterLabel(HistoryFilter.expenseCategories(ids), _cats);
    expect(label({'a', 'b', 'c'}), 'Фильтр: Расходы · 3 категории');
    expect(label({'a', 'b', 'c', 'd'}), 'Фильтр: Расходы · 4 категории');
    expect(label({'a', 'b', 'c', 'd', 'e'}), 'Фильтр: Расходы · 5 категорий');
  });

  test('тип «Все» с ограничением только расходов', () {
    expect(
      historyFilterLabel(const HistoryFilter(expenseCategoryIds: {'a'}), _cats),
      'Фильтр: Расходы · Продукты',
    );
  });

  test('тип «Все» с ограничением только доходов', () {
    expect(
      historyFilterLabel(const HistoryFilter(incomeCategoryIds: {'a'}), _cats),
      'Фильтр: Доходы · Продукты',
    );
  });

  test('архивная категория — своим именем', () {
    expect(
      historyFilterLabel(const HistoryFilter.expenseCategories({'old'}), _cats),
      'Фильтр: Расходы · Старая',
    );
  });

  test('пустой набор и неизвестная категория', () {
    expect(
      historyFilterLabel(const HistoryFilter.expenseCategories({}), _cats),
      'Фильтр: Расходы · нет категорий',
    );
    expect(
      historyFilterLabel(const HistoryFilter.expenseCategories({'zzz'}), _cats),
      'Фильтр: Расходы · Без категории',
    );
  });
}
