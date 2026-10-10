import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/category_totals.dart';
import 'package:money_app/features/analytics/domain/period_summary.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Изменение в процентах, целое, округление «половина от нуля»
/// (ADR 0012, п. 4). Считается только целыми числами:
/// `(|разница| * 100 * 2 + прошлое) ~/ (прошлое * 2)` со знаком разницы.
///
/// Прошлое равно нулю — `null` (процента нет, на экране «раньше не было»).
/// Отрицательные суммы не бывают — [ArgumentError].
int? percentChange(int current, int previous) {
  if (current < 0 || previous < 0) {
    throw ArgumentError('Amounts must be >= 0: $current, $previous');
  }
  if (previous == 0) return null;
  final difference = current - previous;
  final magnitude = (difference.abs() * 200 + previous) ~/ (previous * 2);
  return difference < 0 ? -magnitude : magnitude;
}

/// Сумма «сейчас» против суммы «было».
class AmountChange {
  const AmountChange({required this.current, required this.previous});

  final Money current;
  final Money previous;

  /// Сейчас минус было: отрицательная, если стало меньше.
  Money get difference => current - previous;

  /// Процент изменения или `null`, если раньше было 0.
  int? get percent => percentChange(current.minorUnits, previous.minorUnits);
}

/// Сравнение одной категории верхнего уровня.
final class CategoryComparison extends AmountChange {
  const CategoryComparison({
    required this.categoryId,
    required super.current,
    required super.previous,
  });

  final String categoryId;
}

/// Итог периода [current] против [previous] для операций вида [type].
AmountChange comparePeriodTotals(
  Iterable<Transaction> transactions,
  DateRange current,
  DateRange previous, {
  required TransactionType type,
  required String currency,
}) {
  Money totalOf(DateRange range) {
    final summary = summarizePeriod(transactions, range, currency: currency);
    return type == TransactionType.expense ? summary.expense : summary.income;
  }

  return AmountChange(current: totalOf(current), previous: totalOf(previous));
}

/// Сравнение по категориям верхнего уровня (подкатегории сводятся к
/// категории). Порядок: сначала категории с суммой «сейчас» по убыванию,
/// затем исчезнувшие (сейчас 0) по сумме «было» по убыванию; ничья — по
/// `categoryId`. Категории без сумм в обоих периодах в список не попадают.
///
/// Операция в другой валюте — [ArgumentError].
List<CategoryComparison> compareByCategory(
  Iterable<Transaction> transactions,
  DateRange current,
  DateRange previous, {
  required TransactionType type,
  required String currency,
}) {
  Map<String, Money> totals(DateRange range) => {
    for (final t in totalsByCategory(
      transactions,
      range,
      type: type,
      currency: currency,
    ))
      t.categoryId: t.amount,
  };
  final now = totals(current);
  final before = totals(previous);
  final zero = Money.zero(currency);
  final rows = [
    for (final id in {...now.keys, ...before.keys})
      CategoryComparison(
        categoryId: id,
        current: now[id] ?? zero,
        previous: before[id] ?? zero,
      ),
  ];
  rows.sort((a, b) {
    if (a.current.isZero != b.current.isZero) return a.current.isZero ? 1 : -1;
    final byAmount = a.current.isZero
        ? b.previous.compareTo(a.previous)
        : b.current.compareTo(a.current);
    return byAmount != 0 ? byAmount : a.categoryId.compareTo(b.categoryId);
  });
  return rows;
}
