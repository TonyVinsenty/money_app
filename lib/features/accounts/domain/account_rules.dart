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
    }
  }

  @override
  String toString() => 'AccountRuleException(${rule.name}): $message';
}
