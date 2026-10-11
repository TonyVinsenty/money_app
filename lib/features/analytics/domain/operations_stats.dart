import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Частота и средний чек одной категории верхнего уровня за период.
final class CategoryStat {
  const CategoryStat({
    required this.categoryId,
    required this.count,
    required this.amount,
    required this.average,
  });

  /// Идентификатор категории (подкатегории сведены к ней).
  final String categoryId;

  /// Число операций, включая операции на 0,00 (как в `summarizePeriod`).
  final int count;

  /// Сумма операций (может быть нулевой).
  final Money amount;

  /// Средний чек: `amount.dividedBy(count)`, округление «половина от нуля».
  final Money average;
}

/// Самые крупные операции вида [type] за [period], не больше [limit].
///
/// Порядок: по сумме по убыванию; при равной сумме — более поздний момент
/// (`occurredAt`), затем идентификатор операции по возрастанию, так что
/// результат не зависит от порядка входного списка. Операции на 0,00 в
/// «крупные» не попадают.
///
/// Операции другой валюты — [ArgumentError], как в `summarizePeriod`.
List<Transaction> topTransactions(
  Iterable<Transaction> transactions,
  DateRange period,
  TransactionType type, {
  required String currency,
  int limit = 10,
}) {
  if (limit < 0) throw ArgumentError.value(limit, 'limit', 'Must be >= 0');
  final result = [
    for (final transaction in _checkedInPeriod(transactions, period, currency))
      if (transaction.type == type && !transaction.amount.isZero) transaction,
  ];
  result.sort((a, b) {
    final byAmount = b.amount.compareTo(a.amount);
    if (byAmount != 0) return byAmount;
    final byTime = b.occurredAt.compareTo(a.occurredAt);
    if (byTime != 0) return byTime;
    return a.id.compareTo(b.id);
  });
  return result.length <= limit ? result : result.sublist(0, limit);
}

/// Число операций, сумма и средний чек по категориям верхнего уровня.
///
/// Подкатегории считаются в родительскую категорию (в `Transaction` лежит
/// `categoryId` верхнего уровня). Порядок строк: по числу операций по
/// убыванию, при равенстве — по сумме по убыванию, затем по идентификатору;
/// поэтому первая строка и есть «чаще всего» (см. [mostFrequentCategory]).
///
/// Операции другой валюты — [ArgumentError], как в `summarizePeriod`.
List<CategoryStat> categoryStats(
  Iterable<Transaction> transactions,
  DateRange period,
  TransactionType type, {
  required String currency,
}) {
  final amounts = <String, Money>{};
  final counts = <String, int>{};
  for (final transaction in _checkedInPeriod(transactions, period, currency)) {
    if (transaction.type != type) continue;
    final id = transaction.categoryId;
    amounts[id] = (amounts[id] ?? Money.zero(currency)) + transaction.amount;
    counts[id] = (counts[id] ?? 0) + 1;
  }
  final result = [
    for (final id in amounts.keys)
      CategoryStat(
        categoryId: id,
        count: counts[id]!,
        amount: amounts[id]!,
        average: amounts[id]!.dividedBy(counts[id]!),
      ),
  ];
  result.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    if (byCount != 0) return byCount;
    final byAmount = b.amount.compareTo(a.amount);
    if (byAmount != 0) return byAmount;
    return a.categoryId.compareTo(b.categoryId);
  });
  return result;
}

/// «Чаще всего»: категория с наибольшим числом операций; ничья — большая
/// сумма, затем меньший идентификатор. `null`, если операций не было.
CategoryStat? mostFrequentCategory(List<CategoryStat> stats) {
  CategoryStat? best;
  for (final stat in stats) {
    if (best == null) {
      best = stat;
      continue;
    }
    final byCount = stat.count.compareTo(best.count);
    final byAmount = stat.amount.compareTo(best.amount);
    if (byCount > 0 ||
        (byCount == 0 && byAmount > 0) ||
        (byCount == 0 &&
            byAmount == 0 &&
            stat.categoryId.compareTo(best.categoryId) < 0)) {
      best = stat;
    }
  }
  return best;
}

/// Проверяет валюту каждой операции (даже вне периода) и отбирает попавшие
/// в период.
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
