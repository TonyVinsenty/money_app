import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Какие операции показывать по типу.
enum HistoryTypeFilter { all, income, expense }

/// Фильтр «Истории»: тип и наборы категорий верхнего уровня.
///
/// Наборы раздельные для расходов и доходов: смена типа не «съедает» выбор.
/// `null` — «все категории этого вида», пустой набор — «ни одной».
/// Набор расходов не влияет на доходы и наоборот.
final class HistoryFilter {
  /// Наборы копируются в неизменяемые: правка исходного набора снаружи не
  /// должна ломать `==` и `hashCode` (поэтому конструктор не `const`).
  HistoryFilter({
    this.type = HistoryTypeFilter.all,
    Set<String>? expenseCategoryIds,
    Set<String>? incomeCategoryIds,
  }) : expenseCategoryIds = _freeze(expenseCategoryIds),
       incomeCategoryIds = _freeze(incomeCategoryIds);

  /// «Только расходы этих категорий».
  HistoryFilter.expenseCategories(Set<String> ids)
    : type = HistoryTypeFilter.expense,
      expenseCategoryIds = _freeze(ids),
      incomeCategoryIds = null;

  const HistoryFilter._off()
    : type = HistoryTypeFilter.all,
      expenseCategoryIds = null,
      incomeCategoryIds = null;

  /// Фильтр выключен: показываем всё (константа, чтобы годиться в `const`
  /// значения по умолчанию).
  static const off = HistoryFilter._off();

  static Set<String>? _freeze(Set<String>? ids) =>
      ids == null ? null : Set.unmodifiable(ids);

  final HistoryTypeFilter type;

  /// Категории расходов; `null` — все.
  final Set<String>? expenseCategoryIds;

  /// Категории доходов; `null` — все.
  final Set<String>? incomeCategoryIds;

  /// Включён ли фильтр: тип не «все» или задан хотя бы один набор.
  bool get isActive =>
      type != HistoryTypeFilter.all ||
      expenseCategoryIds != null ||
      incomeCategoryIds != null;

  /// Подходит ли операция под фильтр (по `categoryId`, подкатегория
  /// относится к своей категории).
  bool matches(Transaction transaction) {
    final isExpense = transaction.type == TransactionType.expense;
    switch (type) {
      case HistoryTypeFilter.income:
        if (isExpense) return false;
      case HistoryTypeFilter.expense:
        if (!isExpense) return false;
      case HistoryTypeFilter.all:
        break;
    }
    final ids = isExpense ? expenseCategoryIds : incomeCategoryIds;
    return ids == null || ids.contains(transaction.categoryId);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is HistoryFilter &&
            other.type == type &&
            _sameSet(other.expenseCategoryIds, expenseCategoryIds) &&
            _sameSet(other.incomeCategoryIds, incomeCategoryIds);
  }

  @override
  int get hashCode => Object.hash(
    type,
    _setHash(expenseCategoryIds),
    _setHash(incomeCategoryIds),
  );

  @override
  String toString() =>
      'HistoryFilter(type: ${type.name}, expense: $expenseCategoryIds, '
      'income: $incomeCategoryIds)';
}

bool _sameSet(Set<String>? a, Set<String>? b) {
  if (a == null || b == null) return a == b;
  return a.length == b.length && a.containsAll(b);
}

/// Хеш набора, не зависящий от порядка элементов; `null` отличается от пустого.
int? _setHash(Set<String>? set) {
  if (set == null) return null;
  return set.fold<int>(set.length, (sum, id) => sum ^ id.hashCode);
}

/// Категории верхнего уровня вида [kind] для списка галочек в листе фильтра.
///
/// Живые категории идут по `sortOrder` (при равенстве по имени и id). Архивная
/// показывается, только если по ней есть операции в [monthTransactions] или она
/// уже входит в [selected]. Подкатегории не попадают.
List<Category> historyFilterCategories({
  required Iterable<Category> categories,
  required CategoryKind kind,
  required Iterable<Transaction> monthTransactions,
  required Set<String>? selected,
}) {
  final used = {for (final t in monthTransactions) t.categoryId};
  final result = [
    for (final c in categories)
      if (c.kind == kind &&
          c.isTopLevel &&
          (!c.isArchived ||
              used.contains(c.id) ||
              (selected?.contains(c.id) ?? false)))
        c,
  ];
  result.sort((a, b) {
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    if (byOrder != 0) return byOrder;
    final byName = a.name.compareTo(b.name);
    return byName != 0 ? byName : a.id.compareTo(b.id);
  });
  return result;
}

/// Порядок списка «Истории».
enum HistorySort { newestFirst, oldestFirst, largestFirst, smallestFirst }

/// Отбирает операции по [filter] и сортирует по [sort]. Возвращает новый
/// список, [transactions] не меняется.
///
/// По дате: день, затем момент UTC, затем `id`. По сумме: целые копейки, при
/// равенстве новее выше (день, момент), затем `id`. Разные валюты при
/// сортировке по сумме — [ArgumentError].
List<Transaction> applyHistoryView(
  Iterable<Transaction> transactions,
  HistoryFilter filter,
  HistorySort sort,
) {
  final result = [
    for (final transaction in transactions)
      if (filter.matches(transaction)) transaction,
  ];
  final byAmount =
      sort == HistorySort.largestFirst || sort == HistorySort.smallestFirst;
  if (byAmount && result.isNotEmpty) {
    final currency = result.first.amount.currency;
    for (final transaction in result) {
      if (transaction.amount.currency != currency) {
        throw ArgumentError.value(
          transaction.amount.currency,
          'currency',
          'Expected $currency for every transaction',
        );
      }
    }
  }
  int Function(Transaction, Transaction) compare;
  switch (sort) {
    case HistorySort.newestFirst:
      compare = (a, b) => _byDate(b, a);
    case HistorySort.oldestFirst:
      compare = _byDate;
    case HistorySort.largestFirst:
      compare = (a, b) => _byAmount(a, b, descending: true);
    case HistorySort.smallestFirst:
      compare = (a, b) => _byAmount(a, b, descending: false);
  }
  result.sort(compare);
  return result;
}

int _byDate(Transaction a, Transaction b) {
  final byDay = a.occurredOn.compareTo(b.occurredOn);
  if (byDay != 0) return byDay;
  final byMoment = a.occurredAt.compareTo(b.occurredAt);
  if (byMoment != 0) return byMoment;
  return a.id.compareTo(b.id);
}

/// По сумме (по возрастанию, при [descending] — по убыванию). При равенстве
/// в обоих направлениях: новее выше (день, момент), затем `id` по возрастанию.
int _byAmount(Transaction a, Transaction b, {required bool descending}) {
  final byMinor = a.amount.minorUnits.compareTo(b.amount.minorUnits);
  if (byMinor != 0) return descending ? -byMinor : byMinor;
  final byDay = b.occurredOn.compareTo(a.occurredOn);
  if (byDay != 0) return byDay;
  final byMoment = b.occurredAt.compareTo(a.occurredAt);
  if (byMoment != 0) return byMoment;
  return a.id.compareTo(b.id);
}
