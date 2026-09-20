import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/features/categories/data/categories_repository_impl.dart';
import 'package:money_app/features/categories/data/default_categories_seeder.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/categories/domain/default_categories.dart';

import '../../../support/fake_id_generator.dart';
import '../../../support/fixed_clock.dart';

/// Генератор, который на вызове номер [collideAt] отдаёт уже выданный id
/// (нарушение уникальности), пока [broken] равно `true`.
final class _CollidingIdGenerator implements IdGenerator {
  _CollidingIdGenerator({required this.collideAt});

  final int collideAt;
  bool broken = true;
  int _calls = 0;
  int _counter = 0;

  @override
  String newId() {
    _calls++;
    if (broken && _calls == collideAt) {
      return 'id-1';
    }
    _counter++;
    return 'id-$_counter';
  }
}

void main() {
  group('DefaultCategoriesSeeder', () {
    late AppDatabase db;
    late FixedClock clock;
    late DriftCategoriesRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      clock = FixedClock(DateTime.utc(2026, 9, 20, 12));
      repo = DriftCategoriesRepository(db, clock: clock);
    });

    tearDown(() async {
      await db.close();
    });

    DefaultCategoriesSeeder seederWith(IdGenerator ids) =>
        DefaultCategoriesSeeder(db, idGenerator: ids, clock: clock);

    Future<int> rowCount() async =>
        (await db.select(db.categories).get()).length;

    Future<List<Category>> top(CategoryKind kind) =>
        repo.watchTopLevel(kind).first;

    test('creates exactly 14 categories on an empty database', () async {
      await seederWith(FakeIdGenerator()).seed();

      expect(await rowCount(), 14);
    });

    test(
      'creates them in the approved order with sortOrder per kind',
      () async {
        await seederWith(FakeIdGenerator()).seed();

        for (final kind in CategoryKind.values) {
          final expected = defaultCategories
              .where((c) => c.kind == kind)
              .toList();
          final actual = await top(kind);

          expect(actual.map((c) => c.name), expected.map((c) => c.name));
          expect(actual.map((c) => c.iconKey), expected.map((c) => c.iconKey));
          expect(actual.map((c) => c.sortOrder), [
            for (var i = 0; i < expected.length; i++) i,
          ]);
          expect(actual.every((c) => c.parentId == null), isTrue);
          expect(actual.every((c) => !c.isArchived), isTrue);
          expect(actual.every((c) => c.kind == kind), isTrue);
        }
        expect(await top(CategoryKind.expense), hasLength(10));
        expect(await top(CategoryKind.income), hasLength(4));
      },
    );

    test('takes ids from the id generator', () async {
      await seederWith(FakeIdGenerator()).seed();

      final all = [
        ...await top(CategoryKind.expense),
        ...await top(CategoryKind.income),
      ];
      expect(all.map((c) => c.id).toSet(), {
        for (var i = 1; i <= 14; i++) 'id-$i',
      });
      // Id выдаются по порядку списка defaultCategories.
      final expenses = await top(CategoryKind.expense);
      expect(expenses.map((c) => c.id), [
        for (var i = 1; i <= 10; i++) 'id-$i',
      ]);
      final incomes = await top(CategoryKind.income);
      expect(incomes.map((c) => c.id), [
        for (var i = 11; i <= 14; i++) 'id-$i',
      ]);
    });

    test('a second call does not duplicate anything', () async {
      final ids = FakeIdGenerator();
      final seeder = seederWith(ids);
      await seeder.seed();
      final before = [
        ...await top(CategoryKind.expense),
        ...await top(CategoryKind.income),
      ];

      await seeder.seed();

      expect(await rowCount(), 14);
      final after = [
        ...await top(CategoryKind.expense),
        ...await top(CategoryKind.income),
      ];
      expect(after, before);
      // Новые id при повторном вызове даже не запрашивались.
      expect(ids.newId(), 'id-15');
    });

    test('does not resurrect or change what the user edited', () async {
      final seeder = seederWith(FakeIdGenerator());
      await seeder.seed();
      final expenses = await top(CategoryKind.expense);
      await repo.rename('id-1', 'Еда');
      await repo.archive('id-2');
      // Меняем порядок: id-3..id-10 идут задом наперёд. Список неполный: id-1
      // и id-2 (архивная) в него не входят.
      await repo.reorder(
        expenses.skip(2).map((c) => c.id).toList().reversed.toList(),
      );
      // Переданные получают 0..7; id-1 и id-2 сохраняют прежнее положение
      // друг относительно друга и встают следом: 8 и 9. Дублей нет.
      final expenseRows = (await db.select(db.categories).get())
          .where((r) => r.kind == 'expense')
          .toList();
      final sortOrders = {for (final r in expenseRows) r.id: r.sortOrder};
      expect(sortOrders, {
        for (var i = 0; i < 8; i++) 'id-${10 - i}': i,
        'id-1': 8,
        'id-2': 9,
      });
      expect(sortOrders.values.toSet(), hasLength(10));
      // Семья доходов перестановкой расходов не затронута: id-11..id-14 -> 0..3.
      final incomeRows = (await db.select(db.categories).get())
          .where((r) => r.kind == 'income')
          .toList();
      expect(
        {for (final r in incomeRows) r.id: r.sortOrder},
        {for (var i = 0; i < 4; i++) 'id-${11 + i}': i},
      );
      final before = await db.select(db.categories).get();

      await seeder.seed();

      expect(await rowCount(), 14);
      final after = await db.select(db.categories).get();
      expect(after, unorderedEquals(before));
      final renamed = await repo.findById('id-1');
      expect(renamed!.name, 'Еда');
      expect((await repo.findById('id-2'))!.isArchived, isTrue);
    });

    test('does not seed again when all categories are archived', () async {
      final seeder = seederWith(FakeIdGenerator());
      await seeder.seed();
      for (var i = 1; i <= 14; i++) {
        await repo.archive('id-$i');
      }

      await seeder.seed();

      expect(await rowCount(), 14);
      expect(await top(CategoryKind.expense), isEmpty);
      expect(await top(CategoryKind.income), isEmpty);
    });

    test('does not seed when the only row is soft-deleted', () async {
      await db.customStatement(
        'INSERT INTO categories (id, kind, name, icon_key, parent_id, '
        'sort_order, archived_at, created_at, updated_at, deleted_at) '
        "VALUES ('raw-1', 'expense', 'Raw', 'icon', NULL, 0, NULL, 1, 1, 5)",
      );

      await seederWith(FakeIdGenerator()).seed();

      expect(await rowCount(), 1);
    });

    test('is atomic: a failure rolls everything back', () async {
      final ids = _CollidingIdGenerator(collideAt: 5);
      final seeder = seederWith(ids);

      await expectLater(seeder.seed(), throwsA(anything));
      expect(await rowCount(), 0);

      ids.broken = false;
      await seeder.seed();

      expect(await rowCount(), 14);
    });
  });
}
