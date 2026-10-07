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

  /// Трёхбуквенный код валюты, например `RUB`.
  TextColumn get currency => text()();

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
    "CHECK (currency GLOB '[A-Z][A-Z][A-Z]')",
  ];
}
