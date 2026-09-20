import 'package:drift/drift.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/features/categories/data/category_mapper.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';

/// Реализация [CategoriesRepository] на drift (ADR 0001).
///
/// Наружу отдаёт только доменные [Category]; классы drift (`CategoryRow`,
/// `CategoriesCompanion`) остаются внутри слоя `data`.
///
/// «Живая» категория: `deleted_at IS NULL AND archived_at IS NULL`. Условие
/// `deleted_at IS NULL` есть в каждом запросе к «живым» строкам: только так
/// SQLite использует частичные индексы схемы (см. `query_plans_test.dart`).
class DriftCategoriesRepository implements CategoriesRepository {
  // `this._clock` в именованном параметре: снаружи он называется `clock`
  // (приватные именованные параметры, Dart 3.12+).
  DriftCategoriesRepository(this._db, {this._clock = const SystemClock()});

  final AppDatabase _db;
  final Clock _clock;

  @override
  Stream<List<Category>> watchTopLevel(CategoryKind kind) {
    final query = _db.select(_db.categories)
      ..where(
        (c) =>
            c.deletedAt.isNull() &
            c.archivedAt.isNull() &
            c.parentId.isNull() &
            c.kind.equals(categoryKindToDb(kind)),
      )
      ..orderBy(_stableOrder);
    return _mapRows(query.watch());
  }

  @override
  Stream<List<Category>> watchSubcategories(String parentId) {
    final query = _db.select(_db.categories)
      ..where(
        (c) =>
            c.deletedAt.isNull() &
            c.archivedAt.isNull() &
            c.parentId.equals(parentId),
      )
      ..orderBy(_stableOrder);
    return _mapRows(query.watch());
  }

  @override
  Future<Category?> findById(String id) async {
    final row = await _liveOrArchivedRow(id);
    return row == null ? null : categoryFromRow(row);
  }

  @override
  Future<bool> hasAny() async {
    // Без условий на deleted_at/archived_at: важна любая строка.
    final rows = await (_db.select(_db.categories)..limit(1)).get();
    return rows.isNotEmpty;
  }

  @override
  Future<void> create(Category category) {
    return _db.transaction(() async {
      final parentId = category.parentId;
      if (parentId != null) {
        final parentRow = await _liveOrArchivedRow(parentId);
        if (parentRow == null) {
          throw ArgumentError.value(
            parentId,
            'parentId',
            'parent category does not exist',
          );
        }
        // Родитель в архиве — не помеха: подкатегорию можно подготовить
        // заранее, она появится вместе с родителем после восстановления.
        Category.checkParent(category, categoryFromRow(parentRow));
      }
      final now = _clock.now();
      // Повторный id не перехватываем: это ошибка программиста, а не
      // ситуация для пользователя. Придёт исключение SQLite о нарушении
      // первичного ключа (UNIQUE constraint failed: categories.id).
      await _db
          .into(_db.categories)
          .insert(
            categoryToCompanion(category, createdAt: now, updatedAt: now),
          );
    });
  }

  @override
  Future<void> rename(String id, String newName) {
    return _db.transaction(() async {
      // Строку в Category НЕ собираем: если имя в базе испорчено (пусто или
      // слишком длинное), сборка бросила бы DataCorruptedException, и
      // починить строку переименованием было бы нельзя. Нужны только
      // существование и то, что строка не удалена.
      await _requireNotDeleted(id);
      final name = Category.checkedName(newName);
      await _updateRow(
        id,
        CategoriesCompanion(name: Value(name), updatedAt: Value(_nowMs())),
      );
    });
  }

  @override
  Future<void> reorder(List<String> orderedIds) {
    if (orderedIds.isEmpty) {
      return Future<void>.value();
    }
    if (orderedIds.toSet().length != orderedIds.length) {
      return Future<void>.error(
        ArgumentError.value(orderedIds, 'orderedIds', 'contains duplicates'),
      );
    }
    // Транзакция: либо применяются все перестановки, либо ни одной.
    return _db.transaction(() async {
      final rows = await (_db.select(
        _db.categories,
      )..where((c) => c.deletedAt.isNull() & c.id.isIn(orderedIds))).get();
      final byId = {for (final row in rows) row.id: row};

      for (final id in orderedIds) {
        if (!byId.containsKey(id)) {
          throw ArgumentError.value(id, 'orderedIds', 'category not found');
        }
      }
      final first = byId[orderedIds.first]!;
      for (final row in rows) {
        if (row.parentId != first.parentId || row.kind != first.kind) {
          throw ArgumentError.value(
            row.id,
            'orderedIds',
            'categories must have the same parent and kind',
          );
        }
      }

      // Все не удалённые «братья» (в том числе архивные) в текущем порядке.
      final parentId = first.parentId;
      final siblings =
          await (_db.select(_db.categories)
                ..where(
                  (c) =>
                      c.deletedAt.isNull() &
                      c.kind.equals(first.kind) &
                      (parentId == null
                          ? c.parentId.isNull()
                          : c.parentId.equals(parentId)),
                )
                ..orderBy(_stableOrder))
              .get();

      // Переданные id идут первыми в заданном порядке; остальные братья (не
      // попавшие в список, например архивные) сохраняют прежнее положение и
      // встают следом. Так номера в семье всегда 0..m-1 без повторов.
      final requested = orderedIds.toSet();
      final finalOrder = [
        for (final id in orderedIds) byId[id]!,
        for (final row in siblings)
          if (!requested.contains(row.id)) row,
      ];

      final now = _nowMs();
      for (var i = 0; i < finalOrder.length; i++) {
        final row = finalOrder[i];
        if (row.sortOrder == i) {
          continue; // Уже на месте: строку и updated_at не трогаем.
        }
        await _updateRow(
          row.id,
          CategoriesCompanion(sortOrder: Value(i), updatedAt: Value(now)),
        );
      }
    });
  }

  /// Подкатегории архивируемой категории не трогаем: пока родитель в архиве,
  /// их не показывают (они «висят» под ним), а сами данные и операции по ним
  /// остаются целыми и вернутся вместе с родителем.
  @override
  Future<void> archive(String id) {
    return _db.transaction(() async {
      final row = await _requireRow(id);
      if (row.archivedAt != null) {
        return; // Уже в архиве: время архивации остаётся прежним.
      }
      final now = _nowMs();
      await _updateRow(
        id,
        CategoriesCompanion(archivedAt: Value(now), updatedAt: Value(now)),
      );
    });
  }

  @override
  Future<void> restore(String id) {
    return _db.transaction(() async {
      final row = await _requireRow(id);
      if (row.archivedAt == null) {
        return; // Не в архиве: менять нечего.
      }
      await _updateRow(
        id,
        CategoriesCompanion(
          archivedAt: const Value(null),
          updatedAt: Value(_nowMs()),
        ),
      );
    });
  }

  /// Стабильный порядок: при равном `sort_order` решают время создания и id.
  static final List<OrderingTerm Function($CategoriesTable)> _stableOrder = [
    (c) => OrderingTerm.asc(c.sortOrder),
    (c) => OrderingTerm.asc(c.createdAt),
    (c) => OrderingTerm.asc(c.id),
  ];

  /// Строки потока -> сущности. Если [categoryFromRow] бросит
  /// `DataCorruptedException`, поток получит событие ошибки и продолжит жить.
  Stream<List<Category>> _mapRows(Stream<List<CategoryRow>> rows) {
    return rows.map((list) => list.map(categoryFromRow).toList());
  }

  /// Строка не удалена (`deleted_at IS NULL`); архивные возвращаются.
  Future<CategoryRow?> _liveOrArchivedRow(String id) {
    return (_db.select(
      _db.categories,
    )..where((c) => c.deletedAt.isNull() & c.id.equals(id))).getSingleOrNull();
  }

  /// То же, но отсутствие строки — ошибка вызывающего кода.
  Future<CategoryRow> _requireRow(String id) async {
    final row = await _liveOrArchivedRow(id);
    if (row == null) {
      throw ArgumentError.value(id, 'id', 'category not found');
    }
    return row;
  }

  /// Проверяет, что строка есть и не удалена, не читая её колонки в
  /// `Category`: так работает и с испорченными строками.
  Future<void> _requireNotDeleted(String id) async {
    final table = _db.categories;
    final row =
        await (_db.selectOnly(table)
              ..addColumns([table.id])
              ..where(table.deletedAt.isNull() & table.id.equals(id)))
            .getSingleOrNull();
    if (row == null) {
      throw ArgumentError.value(id, 'id', 'category not found');
    }
  }

  Future<void> _updateRow(String id, CategoriesCompanion changes) {
    return (_db.update(
      _db.categories,
    )..where((c) => c.id.equals(id))).write(changes);
  }

  int _nowMs() => _clock.now().toUtc().millisecondsSinceEpoch;
}
