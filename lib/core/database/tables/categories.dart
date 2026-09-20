import 'package:drift/drift.dart';

/// Категории доходов и расходов (SQL-имя `categories`, ADR 0001).
///
/// Вложенность максимум в один уровень: у категории верхнего уровня
/// `parent_id` равен NULL, у подкатегории он указывает на `categories.id`.
/// Категории не удаляются, а архивируются (`archived_at`); `deleted_at` —
/// мягкое удаление для будущей синхронизации и резервных копий.
///
/// Индексы частичные: в них попадают только «живые» строки
/// (`deleted_at IS NULL`), поэтому они маленькие, а обычная выборка
/// сетки категорий читает только их.
@TableIndex.sql(
  'CREATE INDEX categories_level_order ON categories '
  '(parent_id, sort_order) WHERE deleted_at IS NULL',
)
@TableIndex.sql(
  'CREATE INDEX categories_kind_level_order ON categories '
  '(kind, parent_id, sort_order) WHERE deleted_at IS NULL',
)
class Categories extends Table {
  /// UUID v7, создаётся вне базы (ADR 0001).
  TextColumn get id => text()();

  /// Вид категории: `income` или `expense`. CHECK (см. [customConstraints])
  /// защищает от мусора в базе.
  TextColumn get kind => text()();

  TextColumn get name => text()();

  /// Строковый ключ иконки (не числовой код).
  TextColumn get iconKey => text()();

  /// Внешний ключ на эту же таблицу; NULL — категория верхнего уровня.
  TextColumn get parentId => text().nullable().references(Categories, #id)();

  /// Порядок в сетке внутри своего уровня.
  IntColumn get sortOrder => integer()();

  /// Момент архивации (миллисекунды эпохи UTC); NULL — не в архиве.
  // Именно int, а не DateTime-колонки drift: в базе хранится целое число.
  IntColumn get archivedAt => integer().nullable()();

  IntColumn get createdAt => integer()();

  IntColumn get updatedAt => integer()();

  /// Мягкое удаление (миллисекунды эпохи UTC); NULL — строка «живая».
  IntColumn get deletedAt => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  // Ограничение уровня таблицы, а не колонки: `text().check(kind.isIn(...))`
  // ссылается на собственный геттер, и анализатор ругается на рекурсию.
  @override
  List<String> get customConstraints => [
    "CHECK (kind IN ('income', 'expense'))",
  ];
}
