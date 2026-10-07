import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/accounts/domain/transfer_rules.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';

/// Перевод между двумя счетами: не доход и не расход (ADR 0010).
///
/// Правила проверяются при создании: счета разные и не пустые, сумма больше
/// нуля, момент в UTC, комментарий не длиннее [transactionNoteMaxLength].
/// Совпадение валют со счетами и архивность проверяет репозиторий.
final class Transfer {
  Transfer({
    required this.id,
    required String fromAccountId,
    required String toAccountId,
    required Money amount,
    required this.occurredOn,
    required DateTime occurredAt,
    String? note,
  }) : fromAccountId = _checkedId(fromAccountId),
       toAccountId = _checkedId(toAccountId),
       amount = _checkedAmount(amount),
       occurredAt = _checkedOccurredAt(occurredAt),
       note = _checkedNote(note) {
    if (fromAccountId == toAccountId) {
      throw TransferRuleException(TransferRule.sameAccount);
    }
  }

  /// Неизменяемый идентификатор (UUID v7).
  final String id;

  /// Счёт, с которого уходят деньги.
  final String fromAccountId;

  /// Счёт, на который приходят деньги.
  final String toAccountId;

  /// Сумма, строго больше нуля.
  final Money amount;

  /// Локальный календарный день перевода.
  final DateOnly occurredOn;

  /// Момент перевода в UTC.
  final DateTime occurredAt;

  /// Комментарий без пробелов по краям; `null` — «нет комментария».
  final String? note;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is Transfer &&
            other.id == id &&
            other.fromAccountId == fromAccountId &&
            other.toAccountId == toAccountId &&
            other.amount == amount &&
            other.occurredOn == occurredOn &&
            other.occurredAt == occurredAt &&
            other.note == note;
  }

  @override
  int get hashCode => Object.hash(
    id,
    fromAccountId,
    toAccountId,
    amount,
    occurredOn,
    occurredAt,
    note,
  );

  @override
  String toString() {
    return 'Transfer(id: $id, from: $fromAccountId, to: $toAccountId, '
        'amount: $amount, occurredOn: $occurredOn, '
        'occurredAt: $occurredAt, note: $note)';
  }

  static String _checkedId(String accountId) {
    if (accountId.trim().isEmpty) {
      throw TransferRuleException(TransferRule.emptyAccountId);
    }
    return accountId;
  }

  static Money _checkedAmount(Money amount) {
    if (amount.minorUnits <= 0) {
      throw TransferRuleException(TransferRule.nonPositiveAmount);
    }
    return amount;
  }

  static DateTime _checkedOccurredAt(DateTime occurredAt) {
    if (!occurredAt.isUtc) {
      throw TransferRuleException(TransferRule.occurredAtNotUtc);
    }
    return occurredAt;
  }

  static String? _checkedNote(String? note) {
    final normalized = normalizeTransactionNote(note);
    if (normalized != null &&
        normalized.runes.length > transactionNoteMaxLength) {
      throw TransferRuleException(TransferRule.noteTooLong);
    }
    return normalized;
  }
}
