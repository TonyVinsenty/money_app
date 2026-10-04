import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Итог одной категории верхнего уровня за период.
final class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.amount,
    required this.count,
  });

  /// Идентификатор категории.
  final String categoryId;

  /// Сумма операций категории за период (больше нуля).
  final Money amount;

  /// Сколько операций вошло в сумму (включая нулевые).
  final int count;
}

/// Итог одной подкатегории внутри категории за период.
final class SubcategoryTotal {
  const SubcategoryTotal({
    required this.subcategoryId,
    required this.amount,
    required this.count,
  });

  /// Идентификатор подкатегории; `null` — «без подкатегории».
  final String? subcategoryId;

  /// Сумма операций группы за период (больше нуля).
  final Money amount;

  /// Сколько операций вошло в сумму (включая нулевые).
  final int count;
}

/// Суммы по категориям верхнего уровня для операций вида [type] за [period].
///
/// Категории с нулевой суммой (например, где были только операции на 0,00)
/// в список не попадают. Порядок: по сумме по убыванию, при равной сумме —
/// по идентификатору категории (названия здесь не известны, их показывает UI).
///
/// Операции другой валюты — [ArgumentError], как в `summarizePeriod`.
List<CategoryTotal> totalsByCategory(
  Iterable<Transaction> transactions,
  DateRange period, {
  required TransactionType type,
  required String currency,
}) {
  final tallies = <String, _Tally>{};
  for (final transaction in _checkedInPeriod(transactions, period, currency)) {
    if (transaction.type != type) continue;
    tallies
        .putIfAbsent(transaction.categoryId, () => _Tally(currency))
        .add(transaction.amount);
  }
  final result = [
    for (final entry in tallies.entries)
      if (!entry.value.amount.isZero)
        CategoryTotal(
          categoryId: entry.key,
          amount: entry.value.amount,
          count: entry.value.count,
        ),
  ];
  result.sort((a, b) {
    final byAmount = b.amount.compareTo(a.amount);
    if (byAmount != 0) return byAmount;
    return a.categoryId.compareTo(b.categoryId);
  });
  return result;
}

/// Суммы по подкатегориям одной категории [categoryId] за [period].
///
/// Операции без подкатегории собираются в группу с `subcategoryId == null`.
/// Группы с нулевой суммой не попадают в список. Порядок: по сумме по
/// убыванию; при равной сумме — по идентификатору, группа «без подкатегории»
/// идёт последней.
List<SubcategoryTotal> subcategoryTotals(
  Iterable<Transaction> transactions,
  DateRange period, {
  required String categoryId,
  required String currency,
}) {
  final tallies = <String?, _Tally>{};
  for (final transaction in _checkedInPeriod(transactions, period, currency)) {
    if (transaction.categoryId != categoryId) continue;
    tallies
        .putIfAbsent(transaction.subcategoryId, () => _Tally(currency))
        .add(transaction.amount);
  }
  final result = [
    for (final entry in tallies.entries)
      if (!entry.value.amount.isZero)
        SubcategoryTotal(
          subcategoryId: entry.key,
          amount: entry.value.amount,
          count: entry.value.count,
        ),
  ];
  result.sort(_bySubcategoryOrder);
  return result;
}

int _bySubcategoryOrder(SubcategoryTotal a, SubcategoryTotal b) {
  final byAmount = b.amount.compareTo(a.amount);
  if (byAmount != 0) return byAmount;
  final idA = a.subcategoryId;
  final idB = b.subcategoryId;
  if (idA == idB) return 0;
  if (idA == null) return 1;
  if (idB == null) return -1;
  return idA.compareTo(idB);
}

/// Проверяет валюту каждой операции (даже вне периода) и отбирает попавшие
/// в период. Так же ведёт себя `summarizePeriod`.
List<Transaction> _checkedInPeriod(
  Iterable<Transaction> transactions,
  DateRange period,
  String currency,
) {
  final result = <Transaction>[];
  for (final transaction in transactions) {
    if (transaction.amount.currency != currency) {
      throw ArgumentError.value(
        transaction.amount.currency,
        'currency',
        'Expected $currency for every transaction',
      );
    }
    if (period.contains(transaction.occurredOn)) result.add(transaction);
  }
  return result;
}

/// Накопитель: сумма и число операций одной группы.
final class _Tally {
  _Tally(String currency) : amount = Money.zero(currency);

  Money amount;
  int count = 0;

  void add(Money value) {
    amount += value;
    count++;
  }
}
