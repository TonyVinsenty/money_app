/// Максимальная длина комментария к операции (после обрезки пробелов).
///
/// Считается в символах (кодовых точках Юникода): `note.runes.length`.
/// Поэтому русская буква и обычный эмодзи занимают по одному символу.
const int transactionNoteMaxLength = 200;

/// Правила операций, которые можно нарушить.
enum TransactionRule {
  /// Сумма отрицательная. Ноль допустим, направление задаёт тип операции.
  negativeAmount,

  /// Комментарий длиннее [transactionNoteMaxLength] символов.
  noteTooLong,

  /// Момент операции `occurredAt` задан не в UTC.
  occurredAtNotUtc,

  /// Идентификатор категории пустой.
  emptyCategoryId,

  /// В качестве категории операции выбрана подкатегория.
  categoryMustBeTopLevel,

  /// Вид категории (доход/расход) не совпадает с типом операции.
  typeKindMismatch,

  /// Подкатегория не принадлежит категории операции.
  subcategoryNotOfCategory,

  /// Категория или подкатегория в архиве: новую операцию в ней создать
  /// нельзя. Проверяет репозиторий (архивность известна только хранилищу).
  categoryArchived,

  /// Счёт в архиве: новую операцию привязать к нему нельзя. Проверяет
  /// репозиторий; у уже существующей привязки не проверяется.
  accountArchived,

  /// Валюта счёта не совпадает с валютой операции. Проверяет репозиторий.
  accountCurrencyMismatch,

  /// Идентификатор счёта задан, но пустой (`null` — «без счёта» — допустим).
  emptyAccountId,
}

/// Ошибка нарушения правила операции.
///
/// Типизированная: по полю [rule] интерфейс выбирает понятный текст для
/// пользователя, а [message] нужен разработчику (логи, тесты).
final class TransactionRuleException implements Exception {
  TransactionRuleException(this.rule, [String? message])
    : message = message ?? _defaultMessage(rule);

  /// Какое правило нарушено.
  final TransactionRule rule;

  /// Описание нарушения по-английски.
  final String message;

  static String _defaultMessage(TransactionRule rule) {
    switch (rule) {
      case TransactionRule.negativeAmount:
        return 'Transaction amount must not be negative';
      case TransactionRule.noteTooLong:
        return 'Transaction note must not be longer than '
            '$transactionNoteMaxLength characters';
      case TransactionRule.occurredAtNotUtc:
        return 'Transaction occurredAt must be in UTC';
      case TransactionRule.emptyCategoryId:
        return 'Transaction category id must not be empty';
      case TransactionRule.categoryMustBeTopLevel:
        return 'Transaction category must be a top-level category';
      case TransactionRule.typeKindMismatch:
        return 'Transaction type must match the kind of its category';
      case TransactionRule.subcategoryNotOfCategory:
        return 'Transaction subcategory must belong to the transaction '
            'category';
      case TransactionRule.categoryArchived:
        return 'Transaction category or subcategory must not be archived';
      case TransactionRule.accountArchived:
        return 'Transaction account must not be archived';
      case TransactionRule.accountCurrencyMismatch:
        return 'Transaction currency must match the currency of its account';
      case TransactionRule.emptyAccountId:
        return 'Transaction account id must not be empty';
    }
  }

  @override
  String toString() => 'TransactionRuleException(${rule.name}): $message';
}

/// Приводит комментарий к виду, в котором он хранится.
///
/// Пробелы по краям обрезаются; пустой результат (в том числе из одних
/// пробелов) означает «комментария нет» и превращается в `null`. Длину не
/// проверяет: это делает сущность операции.
String? normalizeTransactionNote(String? note) {
  if (note == null) {
    return null;
  }
  final trimmed = note.trim();
  return trimmed.isEmpty ? null : trimmed;
}
