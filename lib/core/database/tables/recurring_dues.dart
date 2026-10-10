import 'package:drift/drift.dart';
import 'package:money_app/core/database/converters/date_only_converter.dart';
import 'package:money_app/core/database/tables/recurring_payments.dart';
import 'package:money_app/core/database/tables/transactions.dart';

/// Записи «к оплате» (SQL-имя `recurring_dues`, ADR 0011, пп. 4 и 9).
///
/// Хранятся только наступившие даты (`due_on` не позже «сегодня» на момент
/// создания). Копии суммы нет: неоплаченное берёт сумму из платежа, оплаченное
/// хранит её в своей операции. Уникальный индекс `(payment_id, due_on)` не
/// даёт создать запись дважды.
@DataClassName('RecurringDueRow')
@TableIndex.sql(
  'CREATE UNIQUE INDEX recurring_dues_payment_due ON recurring_dues '
  '(payment_id, due_on)',
)
@TableIndex.sql(
  'CREATE INDEX recurring_dues_transaction ON recurring_dues '
  '(transaction_id) WHERE transaction_id IS NOT NULL',
)
class RecurringDues extends Table {
  /// UUID v7, создаётся вне базы (ADR 0001).
  TextColumn get id => text()();

  TextColumn get paymentId => text().references(RecurringPayments, #id)();

  IntColumn get dueOn => integer().map(const DateOnlyConverter())();

  /// `pending` / `paid` / `skipped`.
  TextColumn get status => text()();

  /// Операция, созданная по кнопке «Оплачено»; только у статуса `paid`.
  TextColumn get transactionId =>
      text().nullable().references(Transactions, #id)();

  /// Когда отмечено (миллисекунды эпохи UTC).
  IntColumn get resolvedAt => integer().nullable()();

  IntColumn get createdAt => integer()();

  IntColumn get updatedAt => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (status IN ('pending', 'paid', 'skipped'))",
    'CHECK (due_on BETWEEN 10101 AND 99991231)',
    "CHECK ((status = 'paid') = (transaction_id IS NOT NULL))",
  ];
}
