import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/categories/domain/category_rules.dart';
import 'package:money_app/features/csv_import/domain/csv_import_failures.dart';
import 'package:money_app/features/csv_import/domain/parse_csv_import.dart';
import 'package:money_app/features/transactions/domain/category_kind_mapping.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:uuid/uuid.dart';

/// Пространство имён для «отпечатков» строк без `ID операции`. Менять нельзя:
/// иначе повторная загрузка старого файла задвоит операции.
const String csvImportFingerprintNamespace =
    '6f1c2a5e-3b7d-4c8a-9e21-5d0b7a4c9f13';

/// Иконка категорий, созданных импортом.
const String csvImportCategoryIconKey = 'more_horiz';

/// Разделитель частей отпечатка (управляющий символ, в именах не встречается).
const String _sep = '\u001F';

/// Итог планирования: что записать и что пропустить. Ничего не пишет сам.
final class CsvImportPlan {
  const CsvImportPlan({
    required this.transactions,
    required this.skippedExisting,
    required this.skippedDeleted,
    required this.categoriesToCreate,
    required this.errors,
  });

  /// Операции к добавлению, в порядке строк файла.
  final List<Transaction> transactions;

  /// Пропущено: такая операция уже есть.
  final int skippedExisting;

  /// Пропущено: такая операция удалена в приложении.
  final int skippedDeleted;

  /// Новые категории и подкатегории в порядке первого появления в файле
  /// (родитель всегда раньше своих подкатегорий).
  final List<Category> categoriesToCreate;

  /// Ошибки строк; если список не пуст, писать нельзя ничего.
  final List<CsvRowError> errors;
}

/// Строит план импорта (ADR 0009, п. 6).
///
/// [categories] — все не удалённые категории и подкатегории, включая
/// архивные. [deletedCategoryIds] — id мягко удалённых категорий: они тоже
/// заняты, новая категория не получит такой id. [liveTransactionIds] и
/// [deletedTransactionIds] — id операций в базе. [ids] даёт id для новых
/// категорий.
CsvImportPlan planCsvImport({
  required List<ParsedCsvRow> rows,
  required List<Category> categories,
  required Set<String> liveTransactionIds,
  required Set<String> deletedTransactionIds,
  required IdGenerator ids,
  Set<String> deletedCategoryIds = const {},
}) {
  final live = {for (final id in liveTransactionIds) id.toLowerCase()};
  final deleted = {for (final id in deletedTransactionIds) id.toLowerCase()};
  final byId = {for (final c in categories) c.id.toLowerCase(): c};
  final taken = {
    ...byId.keys,
    for (final id in deletedCategoryIds) id.toLowerCase(),
  };
  final planned = <Category>[];
  final nextSort = <String, int>{};

  for (final c in categories) {
    final key = _sortKey(c.kind, c.parentId);
    final next = c.sortOrder + 1;
    if (next > (nextSort[key] ?? 0)) nextSort[key] = next;
  }

  final transactions = <Transaction>[];
  final errors = <CsvRowError>[];
  final fingerprintCounts = <String, int>{};
  var skippedExisting = 0;
  var skippedDeleted = 0;

  for (final row in rows) {
    final String id;
    final given = row.transactionId;
    if (given != null) {
      id = given.toLowerCase();
    } else {
      final base = _fingerprintBase(row);
      final n = (fingerprintCounts[base] ?? 0) + 1;
      fingerprintCounts[base] = n;
      id = const Uuid().v5(csvImportFingerprintNamespace, '$base$_sep$n');
    }
    if (live.contains(id)) {
      skippedExisting++;
      continue;
    }
    if (deleted.contains(id)) {
      skippedDeleted++;
      continue;
    }

    final kind = row.type.categoryKind;

    // Сначала только проверки: пока строка может оказаться с ошибкой,
    // в план ничего не попадает.
    var rowFailed = false;
    Category? category;
    final categoryId = row.categoryId?.toLowerCase();
    final byGivenId = categoryId == null ? null : byId[categoryId];
    if (byGivenId != null) {
      if (!byGivenId.isTopLevel) {
        errors.add(CsvCategoryIdIsSubcategory(row.line, row.categoryId!));
        rowFailed = true;
      } else if (byGivenId.kind != kind) {
        errors.add(CsvCategoryKindMismatch(row.line, row.categoryId!));
        rowFailed = true;
      } else {
        category = byGivenId;
      }
    } else {
      category = _findByName(
        [...categories, ...planned],
        kind: kind,
        parentId: null,
        key: categoryNameKey(row.categoryName),
      );
    }

    final subName = row.subcategoryName;
    Category? subcategory;
    final subId = row.subcategoryId?.toLowerCase();
    final bySubId = subId == null ? null : byId[subId];
    if (subName != null && bySubId != null) {
      // Подкатегория по id должна быть дочерней найденной категории; если
      // категории ещё нет (будет создана), чужая подкатегория ей не подойдёт.
      if (bySubId.isTopLevel ||
          category == null ||
          bySubId.parentId != category.id) {
        errors.add(CsvSubcategoryWrongParent(row.line, row.subcategoryId!));
        rowFailed = true;
      } else {
        subcategory = bySubId;
      }
    }
    if (rowFailed) continue;

    // Строка годна: создаём недостающее.
    category ??= _planned(
      planned,
      Category.topLevel(
        id: _freeId(row.categoryId, taken, ids),
        kind: kind,
        name: row.categoryName,
        iconKey: csvImportCategoryIconKey,
        sortOrder: _takeSort(nextSort, kind, null),
      ),
    );
    if (subName != null && subcategory == null) {
      subcategory =
          _findByName(
            [...categories, ...planned],
            kind: kind,
            parentId: category.id,
            key: categoryNameKey(subName),
          ) ??
          _planned(
            planned,
            Category.subcategoryOf(
              id: _freeId(row.subcategoryId, taken, ids),
              parent: category,
              name: subName,
              iconKey: csvImportCategoryIconKey,
              sortOrder: _takeSort(nextSort, kind, category.id),
            ),
          );
    }

    transactions.add(
      Transaction(
        id: id,
        type: row.type,
        amount: row.amount,
        occurredOn: row.day,
        occurredAt: row.occurredAt,
        categoryId: category.id,
        subcategoryId: subcategory?.id,
        note: row.note,
      ),
    );
  }

  return CsvImportPlan(
    transactions: transactions,
    skippedExisting: skippedExisting,
    skippedDeleted: skippedDeleted,
    categoriesToCreate: planned,
    errors: errors,
  );
}

String _fingerprintBase(ParsedCsvRow row) {
  return [
    row.day.toString(),
    row.type.name,
    row.amount.minorUnits.toString(),
    row.amount.currency,
    categoryNameKey(row.categoryName),
    categoryNameKey(row.subcategoryName ?? ''),
    row.note ?? '',
  ].join(_sep);
}

String _sortKey(CategoryKind kind, String? parentId) =>
    '${kind.name}|${parentId ?? ''}';

int _takeSort(Map<String, int> next, CategoryKind kind, String? parentId) {
  final key = _sortKey(kind, parentId);
  final value = next[key] ?? 0;
  next[key] = value + 1;
  return value;
}

Category _planned(List<Category> planned, Category category) {
  planned.add(category);
  return category;
}

/// Id из файла, если он есть и свободен, иначе новый. Занимает выбранный id.
String _freeId(String? fromFile, Set<String> taken, IdGenerator ids) {
  final candidate = fromFile?.toLowerCase();
  final id = candidate != null && !taken.contains(candidate)
      ? candidate
      : ids.newId();
  taken.add(id.toLowerCase());
  return id;
}

Category? _findByName(
  Iterable<Category> pool, {
  required CategoryKind kind,
  required String? parentId,
  required String key,
}) {
  for (final c in pool) {
    if (!c.isArchived &&
        c.kind == kind &&
        c.parentId == parentId &&
        categoryNameKey(c.name) == key) {
      return c;
    }
  }
  return null;
}
