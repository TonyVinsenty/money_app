import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/database/app_database.dart';

void main() {
  group('categories table', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    Future<void> insert(
      String id, {
      String kind = 'expense',
      String name = 'Name',
      String? parentId,
      int sortOrder = 0,
      int? archivedAt,
      int? deletedAt,
    }) {
      return db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: id,
              kind: kind,
              name: name,
              iconKey: 'icon_$id',
              sortOrder: sortOrder,
              createdAt: 1000,
              updatedAt: 2000,
              parentId: Value(parentId),
              archivedAt: Value(archivedAt),
              deletedAt: Value(deletedAt),
            ),
          );
    }

    test('writes a category and reads all fields back', () async {
      await insert('root');
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              id: 'child',
              kind: 'income',
              name: 'Salary',
              iconKey: 'wallet',
              sortOrder: 7,
              createdAt: 1700000000000,
              updatedAt: 1700000001000,
              parentId: const Value('root'),
              archivedAt: const Value(1700000002000),
              deletedAt: const Value(1700000003000),
            ),
          );

      final row = await (db.select(
        db.categories,
      )..where((c) => c.id.equals('child'))).getSingle();

      expect(row.id, 'child');
      expect(row.kind, 'income');
      expect(row.name, 'Salary');
      expect(row.iconKey, 'wallet');
      expect(row.parentId, 'root');
      expect(row.sortOrder, 7);
      expect(row.archivedAt, 1700000002000);
      expect(row.createdAt, 1700000000000);
      expect(row.updatedAt, 1700000001000);
      expect(row.deletedAt, 1700000003000);
    });

    test('nullable columns default to null', () async {
      await insert('root');

      final row = await db.select(db.categories).getSingle();

      expect(row.parentId, isNull);
      expect(row.archivedAt, isNull);
      expect(row.deletedAt, isNull);
    });

    test('top level is selected by parent_id IS NULL', () async {
      await insert('a');
      await insert('b');
      await insert('a1', parentId: 'a');

      final top = await (db.select(
        db.categories,
      )..where((c) => c.parentId.isNull())).get();

      expect(top.map((c) => c.id), unorderedEquals(['a', 'b']));
    });

    test('children are selected by parent_id = ?', () async {
      await insert('a');
      await insert('b');
      await insert('a1', parentId: 'a');
      await insert('a2', parentId: 'a');
      await insert('b1', parentId: 'b');

      final children = await (db.select(
        db.categories,
      )..where((c) => c.parentId.equals('a'))).get();

      expect(children.map((c) => c.id), unorderedEquals(['a1', 'a2']));
    });

    test('rows are sorted by sort_order', () async {
      await insert('c', sortOrder: 30);
      await insert('a', sortOrder: 10);
      await insert('d', sortOrder: 40);
      await insert('b', sortOrder: 20);

      final rows =
          await (db.select(db.categories)
                ..where((c) => c.parentId.isNull())
                ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
              .get();

      expect(rows.map((c) => c.id), ['a', 'b', 'c', 'd']);
    });

    test('reference to a missing parent is rejected', () async {
      await expectLater(
        insert('orphan', parentId: 'no_such_parent'),
        throwsA(
          isA<SqliteException>().having(
            (e) => e.message,
            'message',
            contains('FOREIGN KEY constraint failed'),
          ),
        ),
      );

      expect(await db.select(db.categories).get(), isEmpty);
    });

    test('reference to an existing parent is accepted', () async {
      await insert('root');
      await insert('child', parentId: 'root');

      expect(await db.select(db.categories).get(), hasLength(2));
    });

    test('kind accepts income and expense', () async {
      await insert('i', kind: 'income');
      await insert('e', kind: 'expense');

      final rows = await db.select(db.categories).get();

      expect(rows.map((c) => c.kind), unorderedEquals(['income', 'expense']));
    });

    test('kind other than income or expense is rejected', () async {
      await expectLater(
        insert('bad', kind: 'other'),
        throwsA(
          isA<SqliteException>().having(
            (e) => e.message,
            'message',
            contains('CHECK constraint failed'),
          ),
        ),
      );

      expect(await db.select(db.categories).get(), isEmpty);
    });

    test('soft-deleted and archived rows stay in the table', () async {
      await insert('live');
      await insert('archived', archivedAt: 5000);
      await insert('deleted', deletedAt: 6000);

      final rows = await db.select(db.categories).get();

      expect(
        rows.map((c) => c.id),
        unorderedEquals(['live', 'archived', 'deleted']),
      );
    });

    test('name and icon_key are NOT NULL', () async {
      await expectLater(
        db.customInsert(
          'INSERT INTO categories '
          '(id, kind, icon_key, sort_order, created_at, updated_at) '
          "VALUES ('x', 'expense', 'icon', 0, 1, 1)",
        ),
        throwsA(isA<SqliteException>()),
      );
      await expectLater(
        db.customInsert(
          'INSERT INTO categories '
          '(id, kind, name, sort_order, created_at, updated_at) '
          "VALUES ('y', 'expense', 'Name', 0, 1, 1)",
        ),
        throwsA(isA<SqliteException>()),
      );

      expect(await db.select(db.categories).get(), isEmpty);
    });

    test('columns have expected types and nullability, no REAL', () async {
      final rows = await db.customSelect('PRAGMA table_info(categories)').get();
      final byName = {for (final r in rows) r.read<String>('name'): r};

      String type(String c) => byName[c]!.read<String>('type');
      int notNull(String c) => byName[c]!.read<int>('notnull');

      expect(
        byName.keys,
        unorderedEquals([
          'id',
          'kind',
          'name',
          'icon_key',
          'parent_id',
          'sort_order',
          'archived_at',
          'created_at',
          'updated_at',
          'deleted_at',
        ]),
      );
      expect(byName['id']!.read<int>('pk'), 1);
      for (final c in ['id', 'kind', 'name', 'icon_key']) {
        expect(type(c), 'TEXT', reason: c);
      }
      expect(type('parent_id'), 'TEXT');
      for (final c in [
        'sort_order',
        'archived_at',
        'created_at',
        'updated_at',
        'deleted_at',
      ]) {
        expect(type(c), 'INTEGER', reason: c);
      }
      for (final c in [
        'id',
        'kind',
        'name',
        'icon_key',
        'sort_order',
        'created_at',
        'updated_at',
      ]) {
        expect(notNull(c), 1, reason: c);
      }
      for (final c in ['parent_id', 'archived_at', 'deleted_at']) {
        expect(notNull(c), 0, reason: c);
      }
      expect(byName.keys.where((c) => type(c) == 'REAL'), isEmpty);
    });

    test('foreign key of parent_id points to categories.id', () async {
      final rows = await db
          .customSelect('PRAGMA foreign_key_list(categories)')
          .get();

      expect(rows, hasLength(1));
      expect(rows.single.read<String>('table'), 'categories');
      expect(rows.single.read<String>('from'), 'parent_id');
      expect(rows.single.read<String>('to'), 'id');
    });

    test('partial indexes exist and cover only live rows', () async {
      final list = await db.customSelect('PRAGMA index_list(categories)').get();
      final partial = {
        for (final r in list) r.read<String>('name'): r.read<int>('partial'),
      };

      expect(partial['categories_level_order'], 1);
      expect(partial['categories_kind_level_order'], 1);

      final master = await db
          .customSelect(
            "SELECT name, sql FROM sqlite_master WHERE type = 'index' "
            "AND tbl_name = 'categories' AND sql IS NOT NULL",
          )
          .get();
      final sqlByName = {
        for (final r in master) r.read<String>('name'): r.read<String>('sql'),
      };

      expect(
        sqlByName['categories_level_order'],
        allOf(
          contains('(parent_id, sort_order)'),
          endsWith('deleted_at IS NULL'),
        ),
      );
      expect(
        sqlByName['categories_kind_level_order'],
        allOf(
          contains('(kind, parent_id, sort_order)'),
          endsWith('deleted_at IS NULL'),
        ),
      );
    });
  });
}
