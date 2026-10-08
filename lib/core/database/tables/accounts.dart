import 'package:drift/drift.dart';

/// Счета: банк, наличные, копилка и т. п. (SQL-имя `accounts`, ADR 0010).
///
/// Остаток счёта в базе НЕ хранится: он считается из стартового остатка,
/// операций и переводов. Стартовый остаток может быть отрицательным (долг).
/// Счета не удаляются, а архивируются (`archived_at`); `deleted_at` есть по
/// общему соглашению. Уникальность имени среди не архивных проверяет
/// репозиторий, а не база.
@DataClassName('AccountRow')
@TableIndex.sql(
  'CREATE INDEX accounts_order ON accounts (sort_order) '
  'WHERE deleted_at IS NULL',
)
class Accounts extends Table {
  /// UUID v7, создаётся вне базы (ADR 0001).
  TextColumn get id => text()();

  TextColumn get name => text()();

  /// Строковый ключ значка из постоянного набора.
  TextColumn get iconKey => text()();

  /// Код валюты, 3-10 символов, например `RUB` или `USDT` (ADR 0010, п. 16.4).
  TextColumn get currency => text()();

  /// Знаков после запятой у валюты счёта, 0-8 (ADR 0010, п. 16.4).
  IntColumn get currencyDigits => integer()();

  /// Стартовый остаток в копейках; знак хранится в самом числе.
  IntColumn get openingBalanceMinor => integer()();

  /// Порядок в списке, задаёт пользователь.
  IntColumn get sortOrder => integer()();

  /// Момент архивации (миллисекунды эпохи UTC); NULL — не в архиве.
  IntColumn get archivedAt => integer().nullable()();

  IntColumn get createdAt => integer()();

  IntColumn get updatedAt => integer()();

  /// Мягкое удаление (миллисекунды эпохи UTC); NULL — строка «живая».
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (length(name) BETWEEN 1 AND 40)',
    "CHECK (icon_key <> '')",
    // GLOB чувствителен к регистру; код: 3-10 символов, первая буква.
    'CHECK (length(currency) BETWEEN 3 AND 10 '
        "AND currency GLOB '[A-Z]*' AND currency NOT GLOB '*[^A-Z0-9]*')",
    'CHECK (currency_digits BETWEEN 0 AND 8)',
  ];
}
