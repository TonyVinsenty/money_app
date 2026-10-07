import 'package:money_app/core/money/money.dart';
import 'package:money_app/features/accounts/domain/account.dart';

/// Движения денег по одному счёту (ADR 0010, п. 3), всё в одной валюте.
///
/// Суммы неотрицательные «модули»: направление задаёт название поля.
final class AccountFlows {
  /// Все четыре суммы должны быть в одной валюте, иначе [ArgumentError].
  AccountFlows({
    required this.income,
    required this.expense,
    required this.transfersIn,
    required this.transfersOut,
  }) {
    final currency = income.currency;
    for (final money in [income, expense, transfersIn, transfersOut]) {
      if (money.currency != currency) {
        throw ArgumentError('Currency mismatch in account flows');
      }
      if (money.isNegative) {
        throw ArgumentError('Account flows must not be negative');
      }
    }
  }

  /// Нет движений в валюте [currency].
  AccountFlows.none(String currency)
    : this(
        income: Money.zero(currency),
        expense: Money.zero(currency),
        transfersIn: Money.zero(currency),
        transfersOut: Money.zero(currency),
      );

  /// Доходы, привязанные к счёту.
  final Money income;

  /// Расходы, привязанные к счёту.
  final Money expense;

  /// Переводы на счёт.
  final Money transfersIn;

  /// Переводы со счёта.
  final Money transfersOut;

  /// Валюта движений.
  String get currency => income.currency;

  /// Чистое изменение остатка: доходы + переводы на - расходы - переводы со.
  Money get net => income + transfersIn - expense - transfersOut;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AccountFlows &&
            other.income == income &&
            other.expense == expense &&
            other.transfersIn == transfersIn &&
            other.transfersOut == transfersOut;
  }

  @override
  int get hashCode => Object.hash(income, expense, transfersIn, transfersOut);

  @override
  String toString() =>
      'AccountFlows(income: $income, expense: $expense, '
      'transfersIn: $transfersIn, transfersOut: $transfersOut)';
}

/// Остаток каждого счёта (включая архивные): стартовый + движения.
///
/// [flows] — движения по id счёта; счёта без записи считаются без движений.
/// Валюта движений не совпала с валютой счёта — [ArgumentError].
Map<String, Money> computeAccountBalances(
  Iterable<Account> accounts,
  Map<String, AccountFlows> flows,
) {
  final result = <String, Money>{};
  for (final account in accounts) {
    final accountFlows = flows[account.id];
    if (accountFlows == null) {
      result[account.id] = account.openingBalance;
      continue;
    }
    if (accountFlows.currency != account.currency) {
      throw ArgumentError(
        'Currency mismatch for account ${account.id}: '
        '${account.currency} and ${accountFlows.currency}',
      );
    }
    result[account.id] = account.openingBalance + accountFlows.net;
  }
  return result;
}

/// «Всего на счетах»: сумма остатков только не архивных счетов в [currency].
///
/// Архивные счета и не архивные счета другой валюты пропускаются. Для не
/// архивного счёта в [currency] без записи в [balances] бросает
/// [ArgumentError].
Money totalOnAccounts(
  Iterable<Account> accounts,
  Map<String, Money> balances, {
  required String currency,
}) {
  var total = Money.zero(currency);
  for (final account in accounts) {
    if (account.isArchived || account.currency != currency) continue;
    final balance = balances[account.id];
    if (balance == null) {
      throw ArgumentError('No balance for account ${account.id}');
    }
    total += balance;
  }
  return total;
}

/// Стартовый остаток, при котором текущий остаток станет ровно [entered]
/// («Поправить остаток»): введённое минус движения. Другая валюта движений
/// — [ArgumentError].
Money openingForCurrentBalance(Money entered, AccountFlows flows) {
  return entered - flows.net;
}
