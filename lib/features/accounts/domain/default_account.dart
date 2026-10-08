import 'package:money_app/features/accounts/domain/account.dart';

/// Основной счёт среди [accounts] или `null`, если его нет.
///
/// [storedId] - то, что записано в настройках. Основным считается счёт с этим
/// id, только если он не в архиве и в основной валюте [mainCurrency]
/// (ADR 0010, п. 16.10). Запись в настройках при этом не меняется: вернулся
/// счёт из архива или основная валюта - основной снова есть.
Account? resolveDefaultAccount(
  Iterable<Account> accounts,
  String? storedId,
  String mainCurrency,
) {
  if (storedId == null) return null;
  for (final a in accounts) {
    if (a.id == storedId && !a.isArchived && a.currency == mainCurrency) {
      return a;
    }
  }
  return null;
}

/// Кто становится основным, когда в архив уходит основной счёт [archived]:
/// первый по порядку (`sortOrder`) активный счёт той же валюты среди
/// [accounts]; `null`, если такого нет.
Account? nextDefaultAfterArchive(Account archived, Iterable<Account> accounts) {
  Account? best;
  for (final a in accounts) {
    if (a.id == archived.id || a.isArchived) continue;
    if (a.currency != archived.currency) continue;
    if (best == null || a.sortOrder < best.sortOrder) best = a;
  }
  return best;
}
