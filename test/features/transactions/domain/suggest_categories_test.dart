import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/suggest_categories.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

Category _top(String id, {CategoryKind kind = CategoryKind.expense}) =>
    Category.topLevel(
      id: id,
      kind: kind,
      name: 'Cat $id',
      iconKey: 'icon',
      sortOrder: 0,
    );

Category _sub(Category parent, String id) => Category.subcategoryOf(
  id: id,
  parent: parent,
  name: 'Sub $id',
  iconKey: 'icon',
  sortOrder: 0,
);

var _seq = 0;

/// Операция в местное время [local] (в UTC переводится здесь, чтобы тесты не
/// зависели от часового пояса машины).
Transaction _op(
  Category category, {
  Category? sub,
  required DateTime local,
  TransactionType type = TransactionType.expense,
}) {
  _seq++;
  return Transaction(
    id: 't$_seq',
    type: type,
    amount: Money.fromMinor(100, 'RUB'),
    occurredOn: DateOnly(local.year, local.month, local.day),
    occurredAt: local.toUtc(),
    categoryId: category.id,
    subcategoryId: sub?.id,
  );
}

List<Transaction> _times(
  int n,
  Category category, {
  Category? sub,
  required DateTime local,
  TransactionType type = TransactionType.expense,
}) => [
  for (var i = 0; i < n; i++) _op(category, sub: sub, local: local, type: type),
];

List<CategorySuggestion> _suggest(
  List<Transaction> ops,
  DateTime now,
  List<Category> cats, {
  TransactionType type = TransactionType.expense,
}) => suggestCategories(
  recent: ops,
  now: now.toUtc(),
  categories: cats,
  type: type,
);

void main() {
  final food = _top('food');
  final cafe = _sub(food, 'cafe');
  final taxi = _top('taxi');
  final cats = [food, cafe, taxi];

  // Все «старые» операции: 40 дней назад, вне 30-дневного окна.
  DateTime old(int hour, [int minute = 0]) =>
      DateTime(2026, 8, 31, hour, minute);

  test('morning versus evening: time of day decides', () {
    final ops = [
      ..._times(3, food, local: old(9)), // 3 * 3 = 9 утром
      ..._times(4, taxi, local: old(21)), // 4 * 1 = 4
    ];
    final morning = _suggest(ops, DateTime(2026, 10, 10, 9, 30), cats);
    expect(morning.map((s) => s.category.id), ['food', 'taxi']);
    final evening = _suggest(ops, DateTime(2026, 10, 10, 21, 0), cats);
    expect(evening.map((s) => s.category.id), ['taxi', 'food']);
  });

  test('time window is inclusive at 2 hours and excludes 2h01', () {
    final ops = [
      ..._times(3, food, local: old(11)), // ровно +2 ч от 9:00: ×3 = 9
      ..._times(8, taxi, local: old(11, 1)), // +2 ч 1 мин: 8
    ];
    final result = _suggest(ops, DateTime(2026, 10, 10, 9, 0), cats);
    expect(result.first.category.id, 'food');
  });

  test('time of day wraps through midnight (23:30 and 00:30 are close)', () {
    final ops = [
      ..._times(3, food, local: old(0, 30)), // 9
      ..._times(4, taxi, local: old(12)), // 4
    ];
    final result = _suggest(ops, DateTime(2026, 10, 10, 23, 30), cats);
    expect(result.first.category.id, 'food');
    final reverse = _suggest(
      [
        ..._times(3, food, local: old(23, 30)),
        ..._times(4, taxi, local: old(12)),
      ],
      DateTime(2026, 10, 10, 0, 30),
      cats,
    );
    expect(reverse.first.category.id, 'food');
  });

  test('last 30 days double the weight', () {
    final ops = [
      ..._times(3, food, local: DateTime(2026, 10, 1, 21)), // 1 * 2 = 6
      ..._times(5, taxi, local: old(21)), // 5
    ];
    final result = _suggest(ops, DateTime(2026, 10, 10, 9), cats);
    expect(result.map((s) => s.category.id), ['food', 'taxi']);
  });

  test('fewer than 3 operations gives nothing', () {
    final ops = _times(2, food, local: DateTime(2026, 10, 9, 9));
    expect(_suggest(ops, DateTime(2026, 10, 10, 9), cats), isEmpty);
    expect(_suggest([], DateTime(2026, 10, 10, 9), cats), isEmpty);
  });

  test('pair with and without subcategory are separate pairs', () {
    final ops = [
      ..._times(3, food, sub: cafe, local: old(9)),
      ..._times(3, food, local: old(21)),
    ];
    final result = _suggest(ops, DateTime(2026, 10, 10, 9), cats);
    expect(result.length, 2);
    expect(result[0].subcategory, cafe);
    expect(result[1].subcategory, isNull);
  });

  test('archived subcategory excludes the pair, not replaces it', () {
    final archivedCafe = cafe.archived(DateTime.utc(2026, 10, 1));
    final ops = _times(5, food, sub: cafe, local: old(9));
    final result = _suggest(ops, DateTime(2026, 10, 10, 9), [
      food,
      archivedCafe,
    ]);
    expect(result, isEmpty);
  });

  test('archived category excludes its pairs', () {
    final ops = _times(5, food, local: old(9));
    final result = _suggest(ops, DateTime(2026, 10, 10, 9), [
      food.archived(DateTime.utc(2026, 10, 1)),
    ]);
    expect(result, isEmpty);
  });

  test('income and expense are separate', () {
    final salary = _top('salary', kind: CategoryKind.income);
    final ops = [
      ..._times(3, salary, local: old(9), type: TransactionType.income),
      ..._times(3, food, local: old(9)),
    ];
    final all = [food, taxi, salary];
    final now = DateTime(2026, 10, 10, 9);
    expect(_suggest(ops, now, all).map((s) => s.category.id), ['food']);
    expect(
      _suggest(
        ops,
        now,
        all,
        type: TransactionType.income,
      ).map((s) => s.category.id),
      ['salary'],
    );
  });

  test('operations older than 90 days are ignored', () {
    final ops = _times(5, food, local: DateTime(2026, 6, 1, 9));
    expect(_suggest(ops, DateTime(2026, 10, 10, 9), cats), isEmpty);
  });

  test('tie goes to the fresher pair, then to ids', () {
    final ops = [
      ..._times(3, food, local: old(9)),
      ..._times(2, taxi, local: old(9)),
      _op(taxi, local: DateTime(2026, 9, 2, 9)), // свежее, вес тот же (3*3)
    ];
    final result = _suggest(ops, DateTime(2026, 10, 10, 9), cats);
    expect(result.map((s) => s.category.id), ['taxi', 'food']);

    // Полная ничья по времени: порядок по id, независимо от порядка входа.
    final same = [
      ..._times(3, taxi, local: old(9)),
      ..._times(3, food, local: old(9)),
    ];
    final a = _suggest(same, DateTime(2026, 10, 10, 9), cats);
    final b = _suggest(same.reversed.toList(), DateTime(2026, 10, 10, 9), cats);
    expect(a.map((s) => s.category.id), ['food', 'taxi']);
    expect(b.map((s) => s.category.id), ['food', 'taxi']);
  });

  test('returns at most 3 suggestions', () {
    final extra = [for (var i = 0; i < 5; i++) _top('c$i')];
    final ops = [for (final c in extra) ..._times(3, c, local: old(9))];
    expect(_suggest(ops, DateTime(2026, 10, 10, 9), extra).length, 3);
  });
}
