import 'package:drift/drift.dart';
import 'package:money_app/core/database/converters/date_only_converter.dart';
import 'package:money_app/core/database/converters/transaction_type_converter.dart';
import 'package:money_app/core/database/tables/accounts.dart';
import 'package:money_app/core/database/tables/categories.dart';

/// Регулярные платежи (SQL-имя `recurring_payments`, ADR 0011, пп. 2 и 9).
///
/// Платёж — план: «каждый месяц 5-го». Расписание задают `unit`, `every` и
/// якорь `starts_on`. Сумма строго положительная, деньги — целые минорные
/// единицы. Согласованность категории, счёта и валюты проверяет репозиторий.
@DataClassName('RecurringPaymentRow')
class RecurringPayments extends Table {
  /// UUID v7, создаётся вне базы (ADR 0001).
  TextColumn get id => text()();

  /// Название 1-40 символов; оно же комментарий создаваемой операции.
  TextColumn get title => text()();

  TextColumn get type => text().map(const TransactionTypeConverter())();

  /// Сумма в копейках, строго больше нуля.
  IntColumn get amountMinor => integer()();

  TextColumn get currency => text()();

  @ReferenceName('recurringPaymentsInCategory')
  TextColumn get categoryId => text().references(Categories, #id)();

  @ReferenceName('recurringPaymentsInSubcategory')
  TextColumn get subcategoryId =>
      text().nullable().references(Categories, #id)();

  /// Счёт платежа; NULL — «без счёта».
  TextColumn get accountId => text().nullable().references(Accounts, #id)();

  /// `week` / `month` / `year`.
  TextColumn get unit => text()();

  /// «Каждые N», 1-99.
  IntColumn get every => integer()();

  /// Дата первого платежа (ГГГГММДД): якорь расписания.
  IntColumn get startsOn => integer().map(const DateOnlyConverter())();

  /// Последний возможный день включительно; NULL — бессрочно.
  IntColumn get endsOn => integer().nullable().map(const DateOnlyConverter())();

  /// Напоминать уведомлением (0/1; CHECK на 0 и 1 добавляет drift).
  BoolColumn get remind => boolean()();

  /// До какого дня включительно уже созданы записи «к оплате» (служебное).
  IntColumn get trackedThrough =>
      integer().nullable().map(const DateOnlyConverter())();

  IntColumn get createdAt => integer()();

  IntColumn get updatedAt => integer()();

  /// Мягкое удаление (миллисекунды эпохи UTC); NULL — строка «живая».
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (length(title) BETWEEN 1 AND 40)',
    "CHECK (type IN ('income', 'expense'))",
    'CHECK (amount_minor > 0)',
    "CHECK (currency GLOB '[A-Z][A-Z][A-Z]')",
    "CHECK (unit IN ('week', 'month', 'year'))",
    'CHECK (every BETWEEN 1 AND 99)',
    'CHECK (starts_on BETWEEN 10101 AND 99991231)',
    'CHECK (ends_on IS NULL OR '
        '(ends_on BETWEEN 10101 AND 99991231 AND ends_on >= starts_on))',
    'CHECK (tracked_through IS NULL OR '
        'tracked_through BETWEEN 10101 AND 99991231)',
  ];
}
