import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/features/categories/domain/category_rules.dart';

/// Максимальная длина имени счёта (после обрезки пробелов).
///
/// Считается в символах (кодовых точках Юникода), как у категорий.
const int accountNameMaxLength = 40;

/// Правила счетов, которые можно нарушить.
enum AccountRule {
  /// Имя пустое или состоит только из пробелов.
  emptyName,

  /// Имя длиннее [accountNameMaxLength] символов.
  nameTooLong,

  /// Ключ значка пустой или состоит только из пробелов.
  emptyIconKey,

  /// Порядок в списке отрицательный.
  negativeSortOrder,

  /// Среди не архивных счетов уже есть счёт с таким именем (без учёта
  /// регистра и пробелов по краям).
  duplicateName,

  /// Знаков после запятой не совпадает с каталогом или с другим счётом той же
  /// валюты (в том числе архивным): у одного кода одна точность.
  currencyDigitsMismatch,
}

/// Ключ для сравнения имён счетов: то же правило, что у категорий.
String accountNameKey(String name) => categoryNameKey(name);

/// Ошибка нарушения правила счёта.
final class AccountRuleException implements Exception {
  AccountRuleException(this.rule, [String? message])
    : message = message ?? _defaultMessage(rule);

  /// Какое правило нарушено.
  final AccountRule rule;

  /// Описание нарушения по-английски.
  final String message;

  static String _defaultMessage(AccountRule rule) {
    switch (rule) {
      case AccountRule.emptyName:
        return 'Account name must not be empty';
      case AccountRule.nameTooLong:
        return 'Account name must not be longer than '
            '$accountNameMaxLength characters';
      case AccountRule.emptyIconKey:
        return 'Account icon key must not be empty';
      case AccountRule.negativeSortOrder:
        return 'Account sort order must not be negative';
      case AccountRule.duplicateName:
        return 'An account with this name already exists';
      case AccountRule.currencyDigitsMismatch:
        return 'Account currency digits differ from the catalog or from '
            'another account with the same currency';
    }
  }

  @override
  String toString() => 'AccountRuleException(${rule.name}): $message';
}

/// Проверяет, что [digits] подходят валюте [currency] (ADR 0010, п. 16.2).
///
/// Валюта каталога - знаки как в каталоге. Иначе, если [existing] (пары
/// «код, знаков» всех счетов, в том числе архивных) уже содержит этот код, -
/// те же знаки. Иначе любые. При нарушении бросает [AccountRuleException] с
/// правилом [AccountRule.currencyDigitsMismatch].
void checkCurrencyDigits({
  required String currency,
  required int digits,
  required Iterable<(String, int)> existing,
}) {
  final known = catalogCurrency(currency);
  if (known != null) {
    if (known.digits != digits) {
      throw AccountRuleException(AccountRule.currencyDigitsMismatch);
    }
    return;
  }
  for (final (code, otherDigits) in existing) {
    if (code == currency && otherDigits != digits) {
      throw AccountRuleException(AccountRule.currencyDigitsMismatch);
    }
  }
}
