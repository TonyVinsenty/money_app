import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Итоги периода: сумма доходов, сумма расходов и число операций каждого вида.
///
/// Баланс не хранится, а считается как доходы минус расходы, поэтому он
/// всегда согласован с суммами. Баланс может быть отрицательным.
final class PeriodSummary {
  const PeriodSummary({
    required this.income,
    required this.expense,
    required this.incomeCount,
    required this.expenseCount,
  });

  /// Сумма доходов за период.
  final Money income;

  /// Сумма расходов за период (положительная, направление задаёт тип).
  final Money expense;

  /// Сколько доходов попало в период (включая нулевые).
  final int incomeCount;

  /// Сколько расходов попало в период (включая нулевые).
  final int expenseCount;

  /// Доходы минус расходы. Отрицательный, если расходов больше.
  Money get balance => income - expense;

  /// Всего операций в периоде.
  int get count => incomeCount + expenseCount;
}

/// Считает итоги операций [transactions], попавших в [period].
///
/// Границы периода входят в него целиком: операция в первый и последний день
/// учитывается. Операции вне периода пропускаются. Сумма ноль увеличивает
/// счётчик, но на суммы не влияет.
///
/// [currency] — валюта, в которой считаем. Операция в другой валюте, даже вне
/// периода, — [ArgumentError]: молча складывать разные валюты нельзя.
PeriodSummary summarizePeriod(
  Iterable<Transaction> transactions,
  DateRange period, {
  required String currency,
}) {
  var income = Money.zero(currency);
  var expense = Money.zero(currency);
  var incomeCount = 0;
  var expenseCount = 0;
  for (final transaction in transactions) {
    if (transaction.amount.currency != currency) {
      throw ArgumentError.value(
        transaction.amount.currency,
        'currency',
        'Expected $currency for every transaction',
      );
    }
    if (!period.contains(transaction.occurredOn)) continue;
    switch (transaction.type) {
      case TransactionType.income:
        income += transaction.amount;
        incomeCount++;
      case TransactionType.expense:
        expense += transaction.amount;
        expenseCount++;
    }
  }
  return PeriodSummary(
    income: income,
    expense: expense,
    incomeCount: incomeCount,
    expenseCount: expenseCount,
  );
}
