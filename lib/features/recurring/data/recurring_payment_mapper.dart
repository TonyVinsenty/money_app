import 'package:drift/drift.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/errors/data_corrupted_exception.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/domain/recurring_rules.dart';

/// Превращает строку базы в доменный [RecurringPayment].
///
/// Нарушение правил (неизвестная единица, валюта вне каталога и т. п.)
/// превращается в [DataCorruptedException] с id строки и причиной в `cause`.
RecurringPayment recurringPaymentFromRow(RecurringPaymentRow row) {
  try {
    final deletedAt = row.deletedAt;
    return RecurringPayment(
      id: row.id,
      title: row.title,
      type: row.type,
      amount: Money.fromMinor(row.amountMinor, row.currency),
      categoryId: row.categoryId,
      subcategoryId: row.subcategoryId,
      accountId: row.accountId,
      unit: _unitFromSql(row.unit),
      every: row.every,
      startsOn: row.startsOn,
      endsOn: row.endsOn,
      remind: row.remind,
      trackedThrough: row.trackedThrough,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        row.createdAt,
        isUtc: true,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        row.updatedAt,
        isUtc: true,
      ),
      deletedAt: deletedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(deletedAt, isUtc: true),
    );
  } catch (error) {
    if (error is RecurringRuleException ||
        error is FormatException ||
        error is ArgumentError) {
      throw DataCorruptedException(
        'Recurring payment row "${row.id}" is corrupted: $error',
        cause: error,
      );
    }
    rethrow;
  }
}

/// Колонки платежа для вставки; времена приходят из `Clock`.
RecurringPaymentsCompanion recurringPaymentToCompanion(
  RecurringPayment payment, {
  required DateTime createdAt,
  required DateTime updatedAt,
}) {
  return RecurringPaymentsCompanion.insert(
    id: payment.id,
    title: payment.title,
    type: payment.type,
    amountMinor: payment.amount.minorUnits,
    currency: payment.amount.currency,
    categoryId: payment.categoryId,
    subcategoryId: Value(payment.subcategoryId),
    accountId: Value(payment.accountId),
    unit: payment.unit.name,
    every: payment.every,
    startsOn: payment.startsOn,
    endsOn: Value(payment.endsOn),
    remind: payment.remind,
    trackedThrough: Value(payment.trackedThrough),
    createdAt: createdAt.toUtc().millisecondsSinceEpoch,
    updatedAt: updatedAt.toUtc().millisecondsSinceEpoch,
  );
}

RepeatUnit _unitFromSql(String text) {
  for (final unit in RepeatUnit.values) {
    if (unit.name == text) return unit;
  }
  throw FormatException('Bad RepeatUnit value in database: "$text"');
}
