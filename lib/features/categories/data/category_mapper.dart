import 'package:drift/drift.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/errors/data_corrupted_exception.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/categories/domain/category_rules.dart';

/// Значения колонки `categories.kind` (на них же держится CHECK в схеме).
const String _kindIncome = 'income';
const String _kindExpense = 'expense';

/// Превращает строку базы в доменную [Category].
///
/// Данные в базе могут оказаться испорченными (ручная правка, ошибка в старой
/// версии, повреждённый файл). Тогда конструктор [Category] бросает
/// [CategoryRuleException] или [ArgumentError], а неизвестный вид даёт
/// [FormatException]. Все они превращаются в [DataCorruptedException] с id
/// строки и исходной причиной в `cause`: верхние слои различают «пользователь
/// ввёл плохое имя» и «в хранилище мусор» (см. [CategoriesRepository]).
///
/// Связь с родителем здесь не проверяется: строка не знает своего родителя.
Category categoryFromRow(CategoryRow row) {
  try {
    final archivedAt = row.archivedAt;
    return Category(
      id: row.id,
      kind: categoryKindFromDb(row.kind),
      name: row.name,
      iconKey: row.iconKey,
      parentId: row.parentId,
      sortOrder: row.sortOrder,
      archivedAt: archivedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(archivedAt, isUtc: true),
    );
  } catch (error) {
    if (error is CategoryRuleException ||
        error is FormatException ||
        error is ArgumentError) {
      throw DataCorruptedException(
        'Category row "${row.id}" is corrupted: $error',
        cause: error,
      );
    }
    rethrow;
  }
}

/// Собирает набор колонок для вставки новой строки из [category].
///
/// Времена [createdAt] и [updatedAt] приходят снаружи (из `Clock`), потому
/// что сущность их не хранит. `deleted_at` не задаётся: у новой строки он
/// `NULL`.
CategoriesCompanion categoryToCompanion(
  Category category, {
  required DateTime createdAt,
  required DateTime updatedAt,
}) {
  return CategoriesCompanion.insert(
    id: category.id,
    kind: categoryKindToDb(category.kind),
    name: category.name,
    iconKey: category.iconKey,
    sortOrder: category.sortOrder,
    createdAt: createdAt.toUtc().millisecondsSinceEpoch,
    updatedAt: updatedAt.toUtc().millisecondsSinceEpoch,
    parentId: Value(category.parentId),
    archivedAt: Value(category.archivedAt?.toUtc().millisecondsSinceEpoch),
  );
}

/// Значение колонки `kind` для [kind]. Явный `switch`, а не `kind.name`:
/// переименование значения перечисления не должно молча менять формат базы.
String categoryKindToDb(CategoryKind kind) {
  switch (kind) {
    case CategoryKind.income:
      return _kindIncome;
    case CategoryKind.expense:
      return _kindExpense;
  }
}

/// Вид по значению колонки `kind`; неизвестное значение — [FormatException].
CategoryKind categoryKindFromDb(String value) {
  switch (value) {
    case _kindIncome:
      return CategoryKind.income;
    case _kindExpense:
      return CategoryKind.expense;
    default:
      throw FormatException('Unknown category kind', value);
  }
}
