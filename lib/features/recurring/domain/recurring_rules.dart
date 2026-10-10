/// Максимальная длина названия регулярного платежа (после обрезки пробелов).
///
/// Считается в символах (кодовых точках Юникода), как у счетов и категорий.
const int recurringTitleMaxLength = 40;

/// Наименьшее значение «каждые N».
const int recurringEveryMin = 1;

/// Наибольшее значение «каждые N».
const int recurringEveryMax = 99;

/// Правила регулярного платежа, которые можно нарушить (ADR 0011, п. 2).
enum RecurringRule {
  /// Название пустое или состоит только из пробелов.
  emptyTitle,

  /// Название длиннее [recurringTitleMaxLength] символов.
  titleTooLong,

  /// Сумма равна нулю или отрицательная: у платежа она строго больше нуля.
  nonPositiveAmount,

  /// «Каждые N» вне диапазона от [recurringEveryMin] до [recurringEveryMax].
  everyOutOfRange,

  /// Дата окончания раньше даты первого платежа.
  endsBeforeStart,

  /// Валюта не обычная (криптовалюта или своя): платёж создаёт операции, а
  /// у них только обычные валюты (ADR 0010, п. 16).
  currencyNotRegular,

  /// Идентификатор платежа, категории, подкатегории или счёта пустой.
  emptyId,

  /// В качестве категории выбрана подкатегория. Проверяет репозиторий.
  categoryMustBeTopLevel,

  /// Вид категории (доход/расход) не совпадает с типом платежа. Проверяет
  /// репозиторий.
  typeKindMismatch,

  /// Подкатегория не принадлежит категории платежа. Проверяет репозиторий.
  subcategoryNotOfCategory,

  /// Категория или подкатегория в архиве. Проверяет репозиторий.
  categoryArchived,

  /// Счёт в архиве. Проверяет репозиторий.
  accountArchived,

  /// Валюта счёта не совпадает с валютой платежа. Проверяет репозиторий.
  accountCurrencyMismatch,
}

/// Ошибка нарушения правила регулярного платежа.
final class RecurringRuleException implements Exception {
  RecurringRuleException(this.rule, [String? message])
    : message = message ?? _defaultMessage(rule);

  /// Какое правило нарушено.
  final RecurringRule rule;

  /// Описание нарушения по-английски.
  final String message;

  static String _defaultMessage(RecurringRule rule) {
    switch (rule) {
      case RecurringRule.emptyTitle:
        return 'Recurring payment title must not be empty';
      case RecurringRule.titleTooLong:
        return 'Recurring payment title must not be longer than '
            '$recurringTitleMaxLength characters';
      case RecurringRule.nonPositiveAmount:
        return 'Recurring payment amount must be greater than zero';
      case RecurringRule.everyOutOfRange:
        return 'Recurring payment "every" must be between '
            '$recurringEveryMin and $recurringEveryMax';
      case RecurringRule.endsBeforeStart:
        return 'Recurring payment must not end before it starts';
      case RecurringRule.currencyNotRegular:
        return 'Recurring payment currency must be a regular (fiat) currency';
      case RecurringRule.emptyId:
        return 'Recurring payment ids must not be empty';
      case RecurringRule.categoryMustBeTopLevel:
        return 'Recurring payment category must be a top-level category';
      case RecurringRule.typeKindMismatch:
        return 'Category kind does not match the recurring payment type';
      case RecurringRule.subcategoryNotOfCategory:
        return 'Subcategory does not belong to the payment category';
      case RecurringRule.categoryArchived:
        return 'Category or subcategory of the recurring payment is archived';
      case RecurringRule.accountArchived:
        return 'Account of the recurring payment is archived';
      case RecurringRule.accountCurrencyMismatch:
        return 'Account currency differs from the recurring payment currency';
    }
  }

  @override
  String toString() => 'RecurringRuleException(${rule.name}): $message';
}
