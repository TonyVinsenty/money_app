import 'package:drift/drift.dart';
import 'package:money_app/core/database/converters/date_only_converter.dart';
import 'package:money_app/core/database/tables/accounts.dart';

/// Переводы между счетами (SQL-имя `transfers`, ADR 0010, п. 8).
///
/// Перевод — не доход и не расход: он меняет остатки двух счетов, но не
/// итоги месяца. Сумма строго положительная, счета разные. Совпадение валюты
/// перевода и счетов, архивность счетов и обрезку пробелов в `note` проверяет
/// репозиторий. Индексы частичные: только «живые» строки.
@DataClassName('TransferRow')
@TableIndex.sql(
  'CREATE INDEX transfers_occurred_on_at ON transfers '
  '(occurred_on, occurred_at) WHERE deleted_at IS NULL',
)
@TableIndex.sql(
  'CREATE INDEX transfers_from_account ON transfers (from_account_id) '
  'WHERE deleted_at IS NULL',
)
@TableIndex.sql(
  'CREATE INDEX transfers_to_account ON transfers (to_account_id) '
  'WHERE deleted_at IS NULL',
)
class Transfers extends Table {
  /// UUID v7, создаётся вне базы (ADR 0001).
  TextColumn get id => text()();

  // Два внешних ключа в одну таблицу: у каждого своё имя обратной ссылки.
  @ReferenceName('transfersFromAccount')
  TextColumn get fromAccountId => text().references(Accounts, #id)();

  @ReferenceName('transfersToAccount')
  TextColumn get toAccountId => text().references(Accounts, #id)();

  /// Сумма в копейках, строго больше нуля.
  IntColumn get amountMinor => integer()();

  TextColumn get currency => text()();

  /// Локальный календарный день (ГГГГММДД), как у операций (ADR 0004).
  IntColumn get occurredOn => integer().map(const DateOnlyConverter())();

  /// Момент перевода: миллисекунды эпохи UTC.
  IntColumn get occurredAt => integer()();

  /// Комментарий от 1 до 200 символов; NULL — комментария нет.
  TextColumn get note => text().nullable()();

  IntColumn get createdAt => integer()();

  IntColumn get updatedAt => integer()();

  /// Мягкое удаление (миллисекунды эпохи UTC); NULL — строка «живая».
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (from_account_id <> to_account_id)',
    'CHECK (amount_minor > 0)',
    "CHECK (currency GLOB '[A-Z][A-Z][A-Z]')",
    'CHECK (occurred_on BETWEEN 10101 AND 99991231)',
    'CHECK (note IS NULL OR length(note) BETWEEN 1 AND 200)',
  ];
}
