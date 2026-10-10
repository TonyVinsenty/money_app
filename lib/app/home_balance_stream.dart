import 'dart:async';

import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/account_balances.dart';
import 'package:money_app/features/accounts/domain/accounts_repository.dart';
import 'package:money_app/features/settings/domain/home_balance_line.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/domain/transactions_repository.dart';

/// Период «за всё время» для итогов: границы входят, годы 1..9999.
final DateRange _allTime = DateRange(DateOnly(1, 1, 1), DateOnly(9999, 12, 31));

/// Поток суммы для строки «Баланс» в центре кольца «Главной» (ADR 0010,
/// п. 13). `null` в потоке - строки нет. Новый поток нужен при смене
/// [line], [currency] или репозиториев. На поток можно подписываться
/// несколько раз, в том числе заново после отписки: у каждого слушателя свои
/// подписки на источники.
///
/// - [HomeBalanceLine.allTime]: все живые доходы минус все живые расходы за
///   всё время в [currency]; операции без счёта входят, переводы лежат в
///   другой таблице и не входят;
/// - [HomeBalanceLine.accounts]: «Всего на счетах» по не архивным счетам в
///   [currency]; таких счетов нет - `null`; пока для нужного счёта нет
///   остатка, событие пропускается (как в секции «Счета»);
/// - [HomeBalanceLine.none]: всегда `null`.
Stream<Money?> watchHomeBalance({
  required HomeBalanceLine line,
  required String currency,
  required TransactionsRepository transactions,
  required AccountsRepository accounts,
}) {
  switch (line) {
    case HomeBalanceLine.none:
      return Stream<Money?>.multi((controller) {
        controller.add(null);
        controller.close();
      });
    case HomeBalanceLine.allTime:
      return _combine<Money, Money, Money?>(
        () => transactions.watchTotal(
          type: TransactionType.income,
          period: _allTime,
          currency: currency,
        ),
        () => transactions.watchTotal(
          type: TransactionType.expense,
          period: _allTime,
          currency: currency,
        ),
        (income, expense) => (value: income - expense),
      );
    case HomeBalanceLine.accounts:
      return _combine<List<Account>, Map<String, Money>, Money?>(
        accounts.watchAll,
        accounts.watchBalances,
        (list, balances) {
          final needed = list.where(
            (a) => !a.isArchived && a.currency == currency,
          );
          if (needed.isEmpty) return (value: null);
          // Счёт уже есть, а остатка ещё нет (потоки приходят порознь):
          // ждём следующего события, а не показываем ошибку.
          if (needed.any((a) => !balances.containsKey(a.id))) return null;
          return (value: totalOnAccounts(list, balances, currency: currency));
        },
      );
  }
}

/// Склеивает два потока: после первого значения из каждого выдаёт результат
/// [combine] на каждое новое. [combine] вернула `null` - событие пропускается.
/// Ошибка источника или самой [combine] уходит в поток ошибкой, поток при
/// этом живёт дальше. Закрывается, когда закрылись оба источника. Источники
/// создаются заново для каждого слушателя.
Stream<R> _combine<A, B, R>(
  Stream<A> Function() makeA,
  Stream<B> Function() makeB,
  ({R value})? Function(A a, B b) combine,
) {
  return Stream<R>.multi((controller) {
    A? lastA;
    B? lastB;
    var hasA = false;
    var hasB = false;
    var open = 2;

    void emit() {
      if (!hasA || !hasB) return;
      try {
        final result = combine(lastA as A, lastB as B);
        if (result != null) controller.add(result.value);
      } on Object catch (error, stack) {
        controller.addError(error, stack);
      }
    }

    void done() {
      if (--open == 0) controller.close();
    }

    final subA = makeA().listen(
      (value) {
        lastA = value;
        hasA = true;
        emit();
      },
      onError: controller.addError,
      onDone: done,
    );
    final subB = makeB().listen(
      (value) {
        lastB = value;
        hasB = true;
        emit();
      },
      onError: controller.addError,
      onDone: done,
    );
    controller.onCancel = () => Future.wait([subA.cancel(), subB.cancel()]);
  });
}
