import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/history_view.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

Category _c(
  String id,
  int order, {
  CategoryKind kind = CategoryKind.expense,
  String? parentId,
  bool archived = false,
}) => Category(
  id: id,
  kind: kind,
  name: 'Имя $id',
  iconKey: 'icon',
  parentId: parentId,
  sortOrder: order,
  archivedAt: archived ? DateTime.utc(2026, 9, 1) : null,
);

Transaction _tx(String categoryId) => Transaction(
  id: 't-$categoryId',
  type: TransactionType.expense,
  amount: Money.fromMinor(100, 'RUB'),
  occurredOn: DateOnly(2026, 9, 12),
  occurredAt: DateTime.utc(2026, 9, 12, 12),
  categoryId: categoryId,
);

List<String> _ids(
  List<Category> all, {
  List<Transaction> txs = const [],
  Set<String>? selected,
  CategoryKind kind = CategoryKind.expense,
}) => [
  for (final c in historyFilterCategories(
    categories: all,
    kind: kind,
    monthTransactions: txs,
    selected: selected,
  ))
    c.id,
];

void main() {
  test('живые категории вида идут по sortOrder', () {
    final all = [
      _c('b', 2),
      _c('a', 1),
      _c('inc', 0, kind: CategoryKind.income),
    ];
    expect(_ids(all), ['a', 'b']);
    expect(_ids(all, kind: CategoryKind.income), ['inc']);
  });

  test('архивная: с операциями в месяце видна, без операций нет', () {
    final all = [_c('a', 1), _c('old', 0, archived: true)];
    expect(_ids(all), ['a']);
    expect(_ids(all, txs: [_tx('old')]), ['old', 'a']);
  });

  test('архивная без операций, но выбранная в фильтре, видна', () {
    final all = [_c('a', 1), _c('old', 0, archived: true)];
    expect(_ids(all, selected: {'old'}), ['old', 'a']);
  });

  test('подкатегории не попадают, даже с операциями', () {
    final all = [_c('a', 0), _c('sub', 0, parentId: 'a')];
    expect(_ids(all, txs: [_tx('sub')]), ['a']);
  });
}
