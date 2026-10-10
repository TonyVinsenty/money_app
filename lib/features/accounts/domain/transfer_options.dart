import 'package:money_app/features/accounts/domain/account.dart';

/// Счета, на которые можно перевести с [from]: не архивные, не сам [from],
/// той же валюты (ADR 0010, п. 16.10).
List<Account> transferTargets(List<Account> all, Account from) => [
  for (final a in all)
    if (!a.isArchived && a.id != from.id && a.currency == from.currency) a,
];

/// Есть ли у [account] пара для перевода: другой не архивный счёт той же валюты.
bool hasTransferPair(List<Account> all, Account account) =>
    !account.isArchived && transferTargets(all, account).isNotEmpty;

/// Можно ли вообще сделать перевод: есть два не архивных счёта одной валюты.
bool canTransferAny(List<Account> all) =>
    all.any((a) => hasTransferPair(all, a));
