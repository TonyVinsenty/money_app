import 'package:drift/drift.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/errors/data_corrupted_exception.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';

/// Превращает строку базы в доменную [Transaction].
///
/// Данные в базе могут оказаться испорченными (ручная правка, ошибка в старой
/// версии, повреждённый файл). Тогда сборка сущности бросает
/// [TransactionRuleException] (например, отрицательная сумма) или
/// [ArgumentError] (например, неверный код валюты). Обе ошибки, а также
/// [FormatException], превращаются в [DataCorruptedException] с id строки и
/// исходной причиной в `cause`.
///
/// Важно: конвертеры колонок `type` и `occurred_on` срабатывают ещё ДО этой
/// функции, внутри drift, когда он читает строку. Их [FormatException] сюда
/// не доходит; её перехватывает репозиторий вокруг самих запросов.
Transaction transactionFromRow(TransactionRow row) {
  try {
    return Transaction(
      id: row.id,
      type: row.type,
      amount: Money.fromMinor(row.amountMinor, row.currency),
      occurredOn: row.occurredOn,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(
        row.occurredAt,
        isUtc: true,
      ),
      categoryId: row.categoryId,
      subcategoryId: row.subcategoryId,
      note: row.note,
      accountId: row.accountId,
    );
  } catch (error) {
    if (error is TransactionRuleException ||
        error is FormatException ||
        error is ArgumentError) {
      throw DataCorruptedException(
        'Transaction row "${row.id}" is corrupted: $error',
        cause: error,
      );
    }
    rethrow;
  }
}

/// Набор колонок для вставки новой строки из [transaction].
///
/// Времена [createdAt] и [updatedAt] приходят снаружи (из `Clock`), потому
/// что сущность их не хранит. `deleted_at` не задаётся: у новой строки он
/// `NULL`.
TransactionsCompanion transactionToInsertCompanion(
  Transaction transaction, {
  required DateTime createdAt,
  required DateTime updatedAt,
}) {
  return TransactionsCompanion.insert(
    id: transaction.id,
    type: transaction.type,
    amountMinor: transaction.amount.minorUnits,
    currency: transaction.amount.currency,
    occurredOn: transaction.occurredOn,
    occurredAt: transaction.occurredAt.toUtc().millisecondsSinceEpoch,
    categoryId: transaction.categoryId,
    subcategoryId: Value(transaction.subcategoryId),
    note: Value(transaction.note),
    accountId: Value(transaction.accountId),
    createdAt: createdAt.toUtc().millisecondsSinceEpoch,
    updatedAt: updatedAt.toUtc().millisecondsSinceEpoch,
  );
}

/// Набор колонок для замены полей существующей строки на поля [transaction].
///
/// Не содержит `id`, `created_at` и `deleted_at`: они при правке не меняются.
/// Необязательные поля (`subcategory_id`, `note`) задаются всегда, чтобы
/// `null` в сущности действительно очищал значение в базе.
TransactionsCompanion transactionToUpdateCompanion(
  Transaction transaction, {
  required DateTime updatedAt,
}) {
  return TransactionsCompanion(
    type: Value(transaction.type),
    amountMinor: Value(transaction.amount.minorUnits),
    currency: Value(transaction.amount.currency),
    occurredOn: Value(transaction.occurredOn),
    occurredAt: Value(transaction.occurredAt.toUtc().millisecondsSinceEpoch),
    categoryId: Value(transaction.categoryId),
    subcategoryId: Value(transaction.subcategoryId),
    note: Value(transaction.note),
    accountId: Value(transaction.accountId),
    updatedAt: Value(updatedAt.toUtc().millisecondsSinceEpoch),
  );
}
