import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Какие операции показывать по типу.
enum HistoryTypeFilter { all, income, expense }

/// Фильтр по счёту: три взаимоисключающих состояния.
sealed class HistoryAccountFilter {
  const HistoryAccountFilter();
}

/// «Все счета» (и операции без счёта тоже).
final class AnyAccount extends HistoryAccountFilter {
  const AnyAccount();

  @override
  bool operator ==(Object other) => other is AnyAccount;

  @override
  int get hashCode => 0;

  @override
  String toString() => 'AnyAccount';
}

/// «Только операции без счёта».
final class NoAccount extends HistoryAccountFilter {
  const NoAccount();

  @override
  bool operator ==(Object other) => other is NoAccount;

  @override
  int get hashCode => 1;

  @override
  String toString() => 'NoAccount';
}

/// «Только операции этого счёта».
final class OneAccount extends HistoryAccountFilter {
  const OneAccount(this.id);

  final String id;

  @override
  bool operator ==(Object other) => other is OneAccount && other.id == id;

  @override
  int get hashCode => Object.hash(2, id);

  @override
  String toString() => 'OneAccount($id)';
}

/// Фильтр «Истории»: тип, наборы категорий верхнего уровня и счёт.
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
    this.accountFilter = const AnyAccount(),
  }) : expenseCategoryIds = _freeze(expenseCategoryIds),
       incomeCategoryIds = _freeze(incomeCategoryIds);

  /// «Только расходы этих категорий».
  HistoryFilter.expenseCategories(Set<String> ids)
    : type = HistoryTypeFilter.expense,
      expenseCategoryIds = _freeze(ids),
      incomeCategoryIds = null,
      accountFilter = const AnyAccount();

  /// «Только операции этого счёта» (кнопка «Операции» на экране счёта).
  HistoryFilter.account(String accountId)
    : type = HistoryTypeFilter.all,
      expenseCategoryIds = null,
      incomeCategoryIds = null,
      accountFilter = OneAccount(accountId);

  const HistoryFilter._off()
    : type = HistoryTypeFilter.all,
      expenseCategoryIds = null,
      incomeCategoryIds = null,
      accountFilter = const AnyAccount();

  /// Тот же фильтр без части про счёт (тип и категории остаются).
  HistoryFilter withAnyAccount() => HistoryFilter(
    type: type,
    expenseCategoryIds: expenseCategoryIds,
    incomeCategoryIds: incomeCategoryIds,
  );

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

  /// Счёт: «все», «без счёта» или «этот счёт».
  final HistoryAccountFilter accountFilter;

  /// Включён ли фильтр: тип не «все», задан хотя бы один набор или счёт.
  bool get isActive =>
      type != HistoryTypeFilter.all ||
      expenseCategoryIds != null ||
      incomeCategoryIds != null ||
      accountFilter is! AnyAccount;

  /// Подходит ли операция под фильтр (по `categoryId`, подкатегория
  /// относится к своей категории).
  bool matches(Transaction transaction) {
    switch (accountFilter) {
      case AnyAccount():
        break;
      case NoAccount():
        if (transaction.accountId != null) return false;
      case OneAccount(:final id):
        if (transaction.accountId != id) return false;
    }
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
            other.accountFilter == accountFilter &&
            _sameSet(other.expenseCategoryIds, expenseCategoryIds) &&
            _sameSet(other.incomeCategoryIds, incomeCategoryIds);
  }

  @override
  int get hashCode => Object.hash(
    type,
    _setHash(expenseCategoryIds),
    _setHash(incomeCategoryIds),
    accountFilter,
  );

  @override
  String toString() =>
      'HistoryFilter(type: ${type.name}, expense: $expenseCategoryIds, '
      'income: $incomeCategoryIds, account: $accountFilter)';
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

/// Текст для сравнения при поиске в «Истории»: без пробелов по краям, в нижнем
/// регистре, «ё» читается как «е».
String normalizeHistorySearch(String text) =>
    text.trim().toLowerCase().replaceAll('ё', 'е');

/// Подходит ли операция под поисковый [query]: запрос входит в комментарий
/// или в имя подкатегории (без учёта регистра, «ё» = «е»). Пустой запрос и
/// запрос из одних пробелов подходят всему.
bool matchesHistorySearch(
  String query, {
  required String? comment,
  required String? subcategoryName,
}) {
  final needle = normalizeHistorySearch(query);
  if (needle.isEmpty) return true;
  bool has(String? text) =>
      text != null && normalizeHistorySearch(text).contains(needle);
  return has(comment) || has(subcategoryName);
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
