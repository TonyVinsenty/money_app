/// Правила переводов между счетами, которые можно нарушить.
enum TransferRule {
  /// Счёт «откуда» совпадает со счётом «куда».
  sameAccount,

  /// Идентификатор одного из счетов пустой.
  emptyAccountId,

  /// Сумма не больше нуля (у перевода ноль — тоже ошибка).
  nonPositiveAmount,

  /// Момент перевода `occurredAt` задан не в UTC.
  occurredAtNotUtc,

  /// Комментарий длиннее допустимого (`transactionNoteMaxLength`).
  noteTooLong,

  /// Новый счёт перевода архивный (проверяет репозиторий).
  accountArchived,

  /// Валюта суммы не равна валюте одного из счетов (проверяет репозиторий).
  currencyMismatch,
}

/// Ошибка нарушения правила перевода.
final class TransferRuleException implements Exception {
  TransferRuleException(this.rule, [String? message])
    : message = message ?? _defaultMessage(rule);

  /// Какое правило нарушено.
  final TransferRule rule;

  /// Описание нарушения по-английски.
  final String message;

  static String _defaultMessage(TransferRule rule) {
    switch (rule) {
      case TransferRule.sameAccount:
        return 'Transfer must go between two different accounts';
      case TransferRule.emptyAccountId:
        return 'Transfer account id must not be empty';
      case TransferRule.nonPositiveAmount:
        return 'Transfer amount must be greater than zero';
      case TransferRule.occurredAtNotUtc:
        return 'Transfer occurredAt must be in UTC';
      case TransferRule.noteTooLong:
        return 'Transfer note is too long';
      case TransferRule.accountArchived:
        return 'Transfer account is archived';
      case TransferRule.currencyMismatch:
        return 'Transfer currency differs from an account currency';
    }
  }

  @override
  String toString() => 'TransferRuleException(${rule.name}): $message';
}
