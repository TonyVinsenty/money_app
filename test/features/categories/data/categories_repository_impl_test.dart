import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/errors/data_corrupted_exception.dart';
import 'package:money_app/features/categories/data/categories_repository_impl.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/categories/domain/category_rules.dart';

import '../../../support/fixed_clock.dart';

/// Записывает всё, что приходит из потока категорий, чтобы тест мог сначала
/// дождаться текущего состояния, потом сделать запись и проверить, что поток
/// сам прислал новый список.
final class _Recorder {
  _Recorder(Stream<List<Category>> stream) {
    _subscription = stream.listen(events.add, onError: errors.add);
  }

  final List<List<Category>> events = [];
  final List<Object> errors = [];
  late final StreamSubscription<List<Category>> _subscription;

  /// Ждёт, пока придёт не меньше [count] событий (до ~2 секунд).
  Future<void> waitForEvents(int count) async {
    for (var i = 0; i < 2000 && events.length < count; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(
      events.length,
      greaterThanOrEqualTo(count),
      reason: 'the stream did not deliver $count events (errors: $errors)',
    );
  }

  /// Идентификаторы по событиям: удобно сравнивать со списком ожидаемого.
  List<List<String>> get ids =>
      events.map((list) => list.map((c) => c.id).toList()).toList();

  /// Даёт потоку время прислать лишние события, если они есть.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 30));

  Future<void> cancel() => _subscription.cancel();
}

void main() {
  group('DriftCategoriesRepository', () {
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

    Category top(
      String id, {
      CategoryKind kind = CategoryKind.expense,
      String? name,
      int sortOrder = 0,
    }) {
      return Category.topLevel(
        id: id,
        kind: kind,
        name: name ?? 'Name $id',
        iconKey: 'icon',
        sortOrder: sortOrder,
      );
    }

    Category child(
      String id,
      String parentId, {
      CategoryKind kind = CategoryKind.expense,
      int sortOrder = 0,
    }) {
      return Category(
        id: id,
        kind: kind,
        name: 'Name $id',
        iconKey: 'icon',
        parentId: parentId,
        sortOrder: sortOrder,
      );
    }

    Future<CategoryRow> rowOf(String id) async {
      final rows = await db.select(db.categories).get();
      return rows.firstWhere((r) => r.id == id);
    }

    /// Строка «в обход» репозитория, в том числе испорченная.
    Future<void> rawInsert(
      String id, {
      String kind = 'expense',
      String name = 'Raw',
      String iconKey = 'icon',
      String? parentId,
      int sortOrder = 0,
      int? archivedAt,
      int? deletedAt,
    }) {
      return db.customStatement(
        'INSERT INTO categories (id, kind, name, icon_key, parent_id, '
        'sort_order, archived_at, created_at, updated_at, deleted_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?, 1, 1, ?)',
        [id, kind, name, iconKey, parentId, sortOrder, archivedAt, deletedAt],
      );
    }

    Future<List<String>> topIds(CategoryKind kind) async {
      final list = await repo.watchTopLevel(kind).first;
      return list.map((c) => c.id).toList();
    }

    Future<_Recorder> record(Stream<List<Category>> stream) async {
      final recorder = _Recorder(stream);
      addTearDown(recorder.cancel);
      await recorder.waitForEvents(1); // текущее состояние
      return recorder;
    }

    group('watchTopLevel', () {
      test('is empty on an empty database', () async {
        expect(await topIds(CategoryKind.expense), isEmpty);
      });

      test('orders by sortOrder and keeps kinds apart', () async {
        await repo.create(top('e2', sortOrder: 2));
        await repo.create(top('e0', sortOrder: 0));
        await repo.create(top('i1', kind: CategoryKind.income, sortOrder: 1));
        await repo.create(top('e1', sortOrder: 1));
        await repo.create(top('i0', kind: CategoryKind.income, sortOrder: 0));

        expect(await topIds(CategoryKind.expense), ['e0', 'e1', 'e2']);
        expect(await topIds(CategoryKind.income), ['i0', 'i1']);
      });

      test('ties are broken by created_at, then by id', () async {
        await repo.create(top('late-a'));
        // Одно время у 'x' и 'y': решает id. 'late-a' создан раньше всех.
        clock.advance(const Duration(seconds: 1));
        await repo.create(top('y'));
        await repo.create(top('x'));

        expect(await topIds(CategoryKind.expense), ['late-a', 'x', 'y']);
      });

      test('does not include subcategories', () async {
        await repo.create(top('p'));
        await repo.create(child('c', 'p'));

        expect(await topIds(CategoryKind.expense), ['p']);
      });

      test('does not include soft-deleted rows', () async {
        await rawInsert('gone', deletedAt: 5);
        await rawInsert('live', sortOrder: 1);

        expect(await topIds(CategoryKind.expense), ['live']);
      });
    });

    group('archive and restore', () {
      test('archived category leaves the live stream but findById returns '
          'it; restore brings it back to the same place', () async {
        await repo.create(top('a', sortOrder: 0));
        await repo.create(top('b', sortOrder: 1));
        await repo.create(top('c', sortOrder: 2));

        clock.advance(const Duration(minutes: 5));
        await repo.archive('b');

        expect(await topIds(CategoryKind.expense), ['a', 'c']);
        final archived = await repo.findById('b');
        expect(archived, isNotNull);
        expect(archived!.name, 'Name b');
        expect(archived.isArchived, isTrue);
        expect(archived.archivedAt, DateTime.utc(2026, 9, 20, 12, 5));

        await repo.restore('b');

        expect(await topIds(CategoryKind.expense), ['a', 'b', 'c']);
        expect((await repo.findById('b'))!.archivedAt, isNull);
      });

      test('archived subcategory leaves watchSubcategories', () async {
        await repo.create(top('p'));
        await repo.create(child('s1', 'p', sortOrder: 0));
        await repo.create(child('s2', 'p', sortOrder: 1));

        await repo.archive('s1');

        final list = await repo.watchSubcategories('p').first;
        expect(list.map((c) => c.id), ['s2']);
      });

      test('archiving a parent leaves its subcategories untouched', () async {
        await repo.create(top('p'));
        await repo.create(child('s', 'p'));

        await repo.archive('p');

        expect((await repo.findById('s'))!.isArchived, isFalse);
        expect(await topIds(CategoryKind.expense), isEmpty);
      });

      test('archive is idempotent: the archive time does not change', () async {
        await repo.create(top('a'));
        clock.advance(const Duration(minutes: 1));
        await repo.archive('a');
        final first = await rowOf('a');

        clock.advance(const Duration(minutes: 10));
        await repo.archive('a');
        final second = await rowOf('a');

        expect(second.archivedAt, first.archivedAt);
        expect(second.updatedAt, first.updatedAt);
      });

      test(
        'restore of a category that is not archived changes nothing',
        () async {
          await repo.create(top('a'));
          final before = await rowOf('a');

          clock.advance(const Duration(minutes: 10));
          await repo.restore('a');

          expect(await rowOf('a'), before);
        },
      );

      test('archive and restore throw ArgumentError for a missing or '
          'deleted category', () async {
        await rawInsert('gone', deletedAt: 5);

        for (final id in ['missing', 'gone']) {
          await expectLater(repo.archive(id), throwsArgumentError);
          await expectLater(repo.restore(id), throwsArgumentError);
        }
      });
    });

    group('live stream updates itself after a write', () {
      test('watchTopLevel: create', () async {
        final rec = await record(repo.watchTopLevel(CategoryKind.expense));
        expect(rec.ids, [<String>[]]);

        await repo.create(top('a'));
        await rec.waitForEvents(2);
        await rec.settle();

        expect(rec.ids, [
          <String>[],
          ['a'],
        ]);
      });

      test('watchTopLevel: create of another kind does not change the '
          'list', () async {
        final rec = await record(repo.watchTopLevel(CategoryKind.expense));

        await repo.create(top('i', kind: CategoryKind.income));
        await rec.settle();

        // drift пересылает список после любой записи в таблицу categories,
        // даже если он не изменился, поэтому событий может быть больше одного;
        // важно, что чужой вид в список не попал.
        expect(rec.ids, everyElement(isEmpty));
      });

      test('watchTopLevel: rename', () async {
        await repo.create(top('a'));
        final rec = await record(repo.watchTopLevel(CategoryKind.expense));

        await repo.rename('a', 'Food');
        await rec.waitForEvents(2);
        await rec.settle();

        expect(rec.events.map((l) => l.map((c) => c.name).toList()), [
          ['Name a'],
          ['Food'],
        ]);
      });

      test('watchTopLevel: reorder', () async {
        await repo.create(top('a', sortOrder: 0));
        await repo.create(top('b', sortOrder: 1));
        final rec = await record(repo.watchTopLevel(CategoryKind.expense));

        await repo.reorder(['b', 'a']);
        await rec.waitForEvents(2);
        await rec.settle();

        expect(rec.ids, [
          ['a', 'b'],
          ['b', 'a'],
        ]);
      });

      test('watchTopLevel: archive and restore', () async {
        await repo.create(top('a', sortOrder: 0));
        await repo.create(top('b', sortOrder: 1));
        final rec = await record(repo.watchTopLevel(CategoryKind.expense));

        await repo.archive('a');
        await rec.waitForEvents(2);
        await repo.restore('a');
        await rec.waitForEvents(3);
        await rec.settle();

        expect(rec.ids, [
          ['a', 'b'],
          ['b'],
          ['a', 'b'],
        ]);
      });

      test(
        'watchAll: includes archived and subcategories, skips deleted',
        () async {
          await repo.create(top('p', sortOrder: 0));
          await repo.create(top('a', sortOrder: 1));
          await repo.create(child('s', 'p'));
          await repo.archive('a');
          await rawInsert('gone', deletedAt: 5);

          final list = await repo.watchAll().first;

          expect(list.map((c) => c.id), unorderedEquals(['p', 'a', 's']));
          expect(list.firstWhere((c) => c.id == 'a').isArchived, isTrue);
        },
      );

      test('watchAll: sends a new list after archive and rename', () async {
        await repo.create(top('a'));
        final rec = await record(repo.watchAll());

        await repo.archive('a');
        await rec.waitForEvents(2);
        await repo.rename('a', 'Bread');
        await rec.waitForEvents(3);
        await rec.settle();

        expect(rec.events.last.single.name, 'Bread');
        expect(rec.events.last.single.isArchived, isTrue);
      });

      test('watchSubcategories: create', () async {
        await repo.create(top('p'));
        final rec = await record(repo.watchSubcategories('p'));
        expect(rec.ids, [<String>[]]);

        await repo.create(child('s', 'p'));
        await rec.waitForEvents(2);
        await rec.settle();

        expect(rec.ids, [
          <String>[],
          ['s'],
        ]);
      });

      test('watchSubcategories: rename', () async {
        await repo.create(top('p'));
        await repo.create(child('s', 'p'));
        final rec = await record(repo.watchSubcategories('p'));

        await repo.rename('s', 'Bread');
        await rec.waitForEvents(2);
        await rec.settle();

        expect(rec.events.map((l) => l.map((c) => c.name).toList()), [
          ['Name s'],
          ['Bread'],
        ]);
      });

      test('watchSubcategories: reorder', () async {
        await repo.create(top('p'));
        await repo.create(child('s1', 'p', sortOrder: 0));
        await repo.create(child('s2', 'p', sortOrder: 1));
        final rec = await record(repo.watchSubcategories('p'));

        await repo.reorder(['s2', 's1']);
        await rec.waitForEvents(2);
        await rec.settle();

        expect(rec.ids, [
          ['s1', 's2'],
          ['s2', 's1'],
        ]);
      });

      test('watchSubcategories: archive and restore', () async {
        await repo.create(top('p'));
        await repo.create(child('s1', 'p', sortOrder: 0));
        await repo.create(child('s2', 'p', sortOrder: 1));
        final rec = await record(repo.watchSubcategories('p'));

        await repo.archive('s1');
        await rec.waitForEvents(2);
        await repo.restore('s1');
        await rec.waitForEvents(3);
        await rec.settle();

        expect(rec.ids, [
          ['s1', 's2'],
          ['s2'],
          ['s1', 's2'],
        ]);
      });

      test('a reorder that changes nothing sends no new event', () async {
        await repo.create(top('a', sortOrder: 0));
        await repo.create(top('b', sortOrder: 1));
        final rec = await record(repo.watchTopLevel(CategoryKind.expense));

        await repo.reorder(['a', 'b']);
        await rec.settle();

        expect(rec.ids, [
          ['a', 'b'],
        ]);
      });
    });

    group('reorder', () {
      test('writes sort_order 0..n-1 in the given order', () async {
        await repo.create(top('a', sortOrder: 5));
        await repo.create(top('b', sortOrder: 9));
        await repo.create(top('c', sortOrder: 12));

        await repo.reorder(['c', 'a', 'b']);

        expect((await rowOf('c')).sortOrder, 0);
        expect((await rowOf('a')).sortOrder, 1);
        expect((await rowOf('b')).sortOrder, 2);
        expect(await topIds(CategoryKind.expense), ['c', 'a', 'b']);
      });

      test('updates updated_at only on rows that changed', () async {
        await repo.create(top('a', sortOrder: 0));
        await repo.create(top('b', sortOrder: 5));
        final created = clock.now().millisecondsSinceEpoch;

        clock.advance(const Duration(minutes: 1));
        await repo.reorder(['a', 'b']);

        expect((await rowOf('a')).updatedAt, created); // уже на месте
        expect(
          (await rowOf('b')).updatedAt,
          clock.now().millisecondsSinceEpoch,
        );
      });

      test('an empty list does nothing', () async {
        await repo.create(top('a', sortOrder: 3));

        await repo.reorder([]);

        expect((await rowOf('a')).sortOrder, 3);
      });

      test('duplicates are an ArgumentError', () async {
        await repo.create(top('a'));
        await repo.create(top('b', sortOrder: 1));

        await expectLater(repo.reorder(['a', 'b', 'a']), throwsArgumentError);
      });

      test('an unknown id is an ArgumentError and changes nothing', () async {
        await repo.create(top('a', sortOrder: 0));
        await repo.create(top('b', sortOrder: 1));

        await expectLater(
          repo.reorder(['b', 'missing', 'a']),
          throwsArgumentError,
        );

        expect(await topIds(CategoryKind.expense), ['a', 'b']);
      });

      test('a soft-deleted id is an ArgumentError', () async {
        await repo.create(top('a'));
        await rawInsert('gone', sortOrder: 1, deletedAt: 5);

        await expectLater(repo.reorder(['gone', 'a']), throwsArgumentError);
      });

      test('a top-level category and a subcategory are not siblings', () async {
        await repo.create(top('p'));
        await repo.create(top('q', sortOrder: 1));
        await repo.create(child('s', 'p'));

        await expectLater(repo.reorder(['q', 's']), throwsArgumentError);
        await expectLater(repo.reorder(['s', 'q']), throwsArgumentError);
      });

      test('subcategories of different parents are not siblings', () async {
        await repo.create(top('p'));
        await repo.create(top('q', sortOrder: 1));
        await repo.create(child('s1', 'p'));
        await repo.create(child('s2', 'q'));

        await expectLater(repo.reorder(['s1', 's2']), throwsArgumentError);
      });

      test('different kinds are not siblings', () async {
        await repo.create(top('e'));
        await repo.create(top('i', kind: CategoryKind.income, sortOrder: 1));

        await expectLater(repo.reorder(['i', 'e']), throwsArgumentError);
      });

      test('archived siblings can be reordered', () async {
        await repo.create(top('a', sortOrder: 0));
        await repo.create(top('b', sortOrder: 1));
        await repo.archive('b');

        await repo.reorder(['b', 'a']);

        expect((await rowOf('b')).sortOrder, 0);
        expect((await rowOf('a')).sortOrder, 1);
      });

      /// sort_order всех не удалённых строк семьи (top-level одного вида или
      /// детей одного родителя) в порядке показа: id -> номер.
      Future<Map<String, int>> familyOrders({
        String? parentId,
        String kind = 'expense',
      }) async {
        final rows = await db.select(db.categories).get();
        final family =
            rows
                .where(
                  (r) =>
                      r.deletedAt == null &&
                      r.parentId == parentId &&
                      r.kind == kind,
                )
                .toList()
              ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        return {for (final r in family) r.id: r.sortOrder};
      }

      /// Номера в семье уникальны и непрерывны: 0..m-1.
      Future<void> expectContiguous({
        String? parentId,
        String kind = 'expense',
      }) async {
        final orders = await familyOrders(parentId: parentId, kind: kind);
        expect(orders.values.toList(), [
          for (var i = 0; i < orders.length; i++) i,
        ]);
      }

      test(
        'a full list: every sibling gets 0..n-1 in the given order',
        () async {
          await repo.create(top('a', sortOrder: 0));
          await repo.create(top('b', sortOrder: 1));
          await repo.create(top('c', sortOrder: 2));

          await repo.reorder(['b', 'c', 'a']);

          expect(await familyOrders(), {'b': 0, 'c': 1, 'a': 2});
          await expectContiguous();
        },
      );

      test('a partial list without archived siblings: the rest keep their '
          'relative order and follow', () async {
        await repo.create(top('a', sortOrder: 0));
        await repo.create(top('b', sortOrder: 1));
        await repo.create(top('c', sortOrder: 2));
        await repo.create(top('d', sortOrder: 3));

        await repo.reorder(['c', 'a']);

        expect(await familyOrders(), {'c': 0, 'a': 1, 'b': 2, 'd': 3});
        await expectContiguous();
        expect(await topIds(CategoryKind.expense), ['c', 'a', 'b', 'd']);
      });

      test('a partial list with an archived sibling: it goes to the tail and '
          'is last after restore', () async {
        await repo.create(top('a', sortOrder: 0));
        await repo.create(top('b', sortOrder: 1));
        await repo.create(top('c', sortOrder: 2));
        await repo.create(top('d', sortOrder: 3));
        await repo.archive('b');

        await repo.reorder(['d', 'c']);

        // 'a' и архивная 'b' не переданы: они встают следом в прежнем порядке.
        expect(await familyOrders(), {'d': 0, 'c': 1, 'a': 2, 'b': 3});
        await expectContiguous();
        expect(await topIds(CategoryKind.expense), ['d', 'c', 'a']);

        await repo.restore('b');

        expect(await topIds(CategoryKind.expense), ['d', 'c', 'a', 'b']);
      });

      test(
        'an empty list changes nothing, even duplicates in the family',
        () async {
          await rawInsert('x', sortOrder: 4);
          await rawInsert('y', sortOrder: 4);
          final before = await db.select(db.categories).get();

          await repo.reorder([]);

          expect(await db.select(db.categories).get(), before);
        },
      );

      test('duplicate sort_order values already in the family are fixed by a '
          'reorder', () async {
        await rawInsert('x', sortOrder: 0);
        await rawInsert('y', sortOrder: 0);
        await rawInsert('z', sortOrder: 0);

        await repo.reorder(['z']);

        // Остальные идут по (sort_order, created_at, id): x, затем y.
        expect(await familyOrders(), {'z': 0, 'x': 1, 'y': 2});
        await expectContiguous();
      });

      test(
        'a partial list of subcategories keeps the family contiguous',
        () async {
          await repo.create(top('p'));
          await repo.create(child('s0', 'p', sortOrder: 0));
          await repo.create(child('s1', 'p', sortOrder: 1));
          await repo.create(child('s2', 'p', sortOrder: 2));
          await repo.archive('s0');

          await repo.reorder(['s2']);

          expect(await familyOrders(parentId: 'p'), {
            's2': 0,
            's0': 1,
            's1': 2,
          });
          await expectContiguous(parentId: 'p');
        },
      );

      test('other families and soft-deleted rows are not touched', () async {
        await repo.create(top('a', sortOrder: 0));
        await repo.create(top('b', sortOrder: 1));
        await repo.create(top('i', kind: CategoryKind.income, sortOrder: 7));
        await repo.create(child('s', 'a', sortOrder: 5));
        await rawInsert('gone', sortOrder: 1, deletedAt: 5);

        await repo.reorder(['b']);

        expect((await rowOf('b')).sortOrder, 0);
        expect((await rowOf('a')).sortOrder, 1);
        expect((await rowOf('i')).sortOrder, 7);
        expect((await rowOf('s')).sortOrder, 5);
        final gone = await rowOf('gone');
        expect(gone.sortOrder, 1);
        expect(gone.updatedAt, 1);
      });

      test('a partial list that changes nothing writes nothing and sends no '
          'event', () async {
        await repo.create(top('a', sortOrder: 0));
        await repo.create(top('b', sortOrder: 1));
        await repo.create(top('c', sortOrder: 2));
        await repo.archive('c');
        final rec = await record(repo.watchTopLevel(CategoryKind.expense));
        final before = await db.select(db.categories).get();
        clock.advance(const Duration(minutes: 1));

        await repo.reorder(['a']);
        await repo.reorder(['a', 'b']);
        await rec.settle();

        expect(await db.select(db.categories).get(), before);
        expect(rec.ids, [
          ['a', 'b'],
        ]);
      });

      test('writes updated_at only for rows whose number changed', () async {
        await repo.create(top('a', sortOrder: 0));
        await repo.create(top('b', sortOrder: 1));
        await repo.create(top('c', sortOrder: 2));
        final created = clock.now().millisecondsSinceEpoch;
        clock.advance(const Duration(minutes: 1));

        await repo.reorder(['b']);

        final now = clock.now().millisecondsSinceEpoch;
        expect((await rowOf('b')).updatedAt, now); // 1 -> 0
        expect((await rowOf('a')).updatedAt, now); // 0 -> 1
        expect((await rowOf('c')).updatedAt, created); // остался 2
      });

      test('the family stays contiguous after a chain of operations', () async {
        for (var i = 0; i < 5; i++) {
          await repo.create(top('t$i', sortOrder: i));
        }
        await expectContiguous();

        await repo.reorder(['t4', 't3']);
        await expectContiguous();
        await repo.archive('t0');
        await expectContiguous();
        await repo.reorder(['t1']);
        await expectContiguous();
        await repo.restore('t0');
        await repo.reorder(['t2', 't0', 't4']);
        await expectContiguous();

        expect(await familyOrders(), {
          't2': 0,
          't0': 1,
          't4': 2,
          't1': 3,
          't3': 4,
        });
      });

      test('is atomic: a failure in the middle leaves the old order', () async {
        await repo.create(top('a', sortOrder: 0));
        await repo.create(top('b', sortOrder: 1));
        await repo.create(top('c', sortOrder: 2));
        await repo.create(top('d', sortOrder: 3));
        // Ловушка в базе: запись sort_order у 'c' падает. Строки 'b', 'a' и
        // 'd' к этому моменту уже записаны, и транзакция обязана их откатить.
        await db.customStatement(
          'CREATE TRIGGER fail_on_c BEFORE UPDATE OF sort_order ON categories '
          "WHEN NEW.id = 'c' BEGIN SELECT RAISE(ABORT, 'boom'); END",
        );

        await expectLater(
          repo.reorder(['b', 'a', 'd', 'c']),
          throwsA(anything),
        );

        expect(await topIds(CategoryKind.expense), ['a', 'b', 'c', 'd']);
        expect((await rowOf('a')).sortOrder, 0);
        expect((await rowOf('b')).sortOrder, 1);
        expect((await rowOf('d')).sortOrder, 3);
      });
    });

    group('create', () {
      test('stores all fields with created_at = updated_at = now', () async {
        await repo.create(top('a', name: 'Food', sortOrder: 4));

        final row = await rowOf('a');
        final now = clock.now().millisecondsSinceEpoch;
        expect(row.kind, 'expense');
        expect(row.name, 'Food');
        expect(row.iconKey, 'icon');
        expect(row.parentId, isNull);
        expect(row.sortOrder, 4);
        expect(row.archivedAt, isNull);
        expect(row.deletedAt, isNull);
        expect(row.createdAt, now);
        expect(row.updatedAt, now);
      });

      test('keeps archivedAt of the entity as is', () async {
        final at = DateTime.utc(2026, 1, 2, 3, 4, 5);

        await repo.create(top('a').archived(at));

        expect((await repo.findById('a'))!.archivedAt, at);
      });

      test('a subcategory is readable through watchSubcategories', () async {
        await repo.create(top('p'));
        await repo.create(child('s1', 'p', sortOrder: 1));
        await repo.create(child('s0', 'p', sortOrder: 0));

        final list = await repo.watchSubcategories('p').first;

        expect(list.map((c) => c.id), ['s0', 's1']);
        expect(list.first.parentId, 'p');
      });

      test('a missing parent is an ArgumentError', () async {
        await expectLater(repo.create(child('s', 'nope')), throwsArgumentError);
        expect(await repo.findById('s'), isNull);
      });

      test('a soft-deleted parent counts as missing', () async {
        await rawInsert('p', deletedAt: 5);

        await expectLater(repo.create(child('s', 'p')), throwsArgumentError);
      });

      test('a subcategory as a parent is parentMustBeTopLevel', () async {
        await repo.create(top('p'));
        await repo.create(child('s', 'p'));

        await expectLater(
          repo.create(child('ss', 's')),
          throwsA(
            isA<CategoryRuleException>().having(
              (e) => e.rule,
              'rule',
              CategoryRule.parentMustBeTopLevel,
            ),
          ),
        );
        expect(await repo.findById('ss'), isNull);
      });

      test('a different kind than the parent is kindMismatch', () async {
        await repo.create(top('p'));

        await expectLater(
          repo.create(child('s', 'p', kind: CategoryKind.income)),
          throwsA(
            isA<CategoryRuleException>().having(
              (e) => e.rule,
              'rule',
              CategoryRule.kindMismatch,
            ),
          ),
        );
      });

      test('an archived parent is allowed', () async {
        await repo.create(top('p'));
        await repo.archive('p');

        await repo.create(child('s', 'p'));

        expect(await repo.findById('s'), isNotNull);
      });

      test('a repeated id is not wrapped: the database error comes out and '
          'the first row stays', () async {
        await repo.create(top('a', name: 'First'));

        await expectLater(
          repo.create(top('a', name: 'Second')),
          throwsA(
            predicate<Object>(
              (e) => e.toString().contains('UNIQUE constraint failed'),
            ),
          ),
        );
        expect((await repo.findById('a'))!.name, 'First');
      });
    });

    group('rename', () {
      test('trims the name and stores it', () async {
        await repo.create(top('a'));

        await repo.rename('a', '  Food  ');

        expect((await repo.findById('a'))!.name, 'Food');
        expect((await rowOf('a')).name, 'Food');
      });

      test('an empty name is emptyName and changes nothing', () async {
        await repo.create(top('a', name: 'Food'));

        await expectLater(
          repo.rename('a', '   '),
          throwsA(
            isA<CategoryRuleException>().having(
              (e) => e.rule,
              'rule',
              CategoryRule.emptyName,
            ),
          ),
        );
        expect((await repo.findById('a'))!.name, 'Food');
      });

      test('41 characters is nameTooLong, 40 is fine', () async {
        await repo.create(top('a'));

        await expectLater(
          repo.rename('a', 'x' * 41),
          throwsA(
            isA<CategoryRuleException>().having(
              (e) => e.rule,
              'rule',
              CategoryRule.nameTooLong,
            ),
          ),
        );
        await repo.rename('a', 'x' * 40);
        expect((await repo.findById('a'))!.name, 'x' * 40);
      });

      test('a missing or deleted category is an ArgumentError', () async {
        await rawInsert('gone', deletedAt: 5);

        await expectLater(repo.rename('missing', 'X'), throwsArgumentError);
        await expectLater(repo.rename('gone', 'X'), throwsArgumentError);
      });

      test('an archived category can be renamed', () async {
        await repo.create(top('a'));
        await repo.archive('a');

        await repo.rename('a', 'Old');

        final found = await repo.findById('a');
        expect(found!.name, 'Old');
        expect(found.isArchived, isTrue);
      });
    });

    group('update', () {
      test('changes name and icon, bumps updatedAt via clock', () async {
        await repo.create(top('a'));
        clock.advance(const Duration(hours: 1));

        await repo.update('a', newName: '  Food ', iconKey: 'cake');

        final found = await repo.findById('a');
        expect(found!.name, 'Food');
        expect(found.iconKey, 'cake');
        expect(
          (await rowOf('a')).updatedAt,
          DateTime.utc(2026, 9, 20, 13).millisecondsSinceEpoch,
        );
      });

      test('createdAt stays the same after update', () async {
        await repo.create(top('a'));
        final created = (await rowOf('a')).createdAt;
        clock.advance(const Duration(hours: 1));

        await repo.update('a', newName: 'B', iconKey: 'cake');

        expect((await rowOf('a')).createdAt, created);
      });

      test('watchAll emits the new icon after update', () async {
        await repo.create(top('a'));
        final recorder = _Recorder(repo.watchAll());
        await recorder.waitForEvents(1);

        await repo.update('a', newName: 'A', iconKey: 'cake');

        await recorder.waitForEvents(2);
        expect(recorder.events.last.single.iconKey, 'cake');
        await recorder.cancel();
      });

      test('children with the old parent icon follow, others stay', () async {
        await repo.create(top('p'));
        await repo.create(child('same', 'p'));
        await repo.create(child('archived', 'p'));
        await repo.archive('archived');
        await rawInsert('own', parentId: 'p', iconKey: 'bolt');
        await rawInsert('gone', parentId: 'p', deletedAt: 5);
        await repo.create(top('other'));
        await repo.create(child('foreign', 'other'));
        clock.advance(const Duration(hours: 1));

        await repo.update('p', newName: 'P', iconKey: 'cake');

        expect((await rowOf('same')).iconKey, 'cake');
        expect((await rowOf('archived')).iconKey, 'cake');
        expect((await rowOf('own')).iconKey, 'bolt');
        expect((await rowOf('gone')).iconKey, 'icon');
        expect((await rowOf('foreign')).iconKey, 'icon');
        expect(
          (await rowOf('same')).updatedAt,
          DateTime.utc(2026, 9, 20, 13).millisecondsSinceEpoch,
        );
        expect((await rowOf('own')).updatedAt, 1);
      });

      test('a subcategory update does not touch anything else', () async {
        await repo.create(top('p'));
        await repo.create(child('c', 'p'));
        await repo.create(child('d', 'p'));

        await repo.update('c', newName: 'C', iconKey: 'cake');

        expect((await rowOf('c')).iconKey, 'cake');
        expect((await rowOf('d')).iconKey, 'icon');
        expect((await rowOf('p')).iconKey, 'icon');
      });

      test('same icon: only the name changes, children untouched', () async {
        await repo.create(top('p'));
        await repo.create(child('c', 'p'));
        clock.advance(const Duration(hours: 1));

        await repo.update('p', newName: 'New', iconKey: 'icon');

        expect((await rowOf('p')).name, 'New');
        expect(
          (await rowOf('c')).updatedAt,
          DateTime.utc(2026, 9, 20, 12).millisecondsSinceEpoch,
        );
      });

      test('a rule violation changes nothing (rolled back)', () async {
        await repo.create(top('a', name: 'Food'));
        await repo.create(top('b', name: 'Fun'));
        await repo.create(child('c', 'a'));

        await expectLater(
          repo.update('a', newName: 'fun', iconKey: 'cake'),
          throwsA(
            isA<CategoryRuleException>().having(
              (e) => e.rule,
              'rule',
              CategoryRule.duplicateName,
            ),
          ),
        );
        await expectLater(
          repo.update('a', newName: 'X', iconKey: '  '),
          throwsA(
            isA<CategoryRuleException>().having(
              (e) => e.rule,
              'rule',
              CategoryRule.emptyIconKey,
            ),
          ),
        );
        await expectLater(
          repo.update('a', newName: ' ', iconKey: 'cake'),
          throwsA(isA<CategoryRuleException>()),
        );
        expect((await rowOf('a')).iconKey, 'icon');
        expect((await rowOf('a')).name, 'Food');
        expect((await rowOf('c')).iconKey, 'icon');
      });

      test('a missing or deleted category is an ArgumentError', () async {
        await rawInsert('gone', deletedAt: 5);

        await expectLater(
          repo.update('missing', newName: 'X', iconKey: 'k'),
          throwsArgumentError,
        );
        await expectLater(
          repo.update('gone', newName: 'X', iconKey: 'k'),
          throwsArgumentError,
        );
      });
    });

    group('duplicate names', () {
      Matcher isDuplicate() => throwsA(
        isA<CategoryRuleException>().having(
          (e) => e.rule,
          'rule',
          CategoryRule.duplicateName,
        ),
      );

      Category sub(String id, String parentId, String name) => Category(
        id: id,
        kind: CategoryKind.expense,
        name: name,
        iconKey: 'icon',
        parentId: parentId,
        sortOrder: 0,
      );

      Future<List<CategoryRow>> allRows() => db.select(db.categories).get();

      test(
        'create rejects the same name in another case with spaces',
        () async {
          await repo.create(top('a', name: 'Такси'));
          final before = await allRows();

          await expectLater(
            repo.create(top('b', name: ' такси ')),
            isDuplicate(),
          );

          expect(await allRows(), before);
          expect(await repo.findById('b'), isNull);
        },
      );

      test('the same name is fine for another kind', () async {
        await repo.create(top('a', name: 'Прочее'));
        await repo.create(top('b', name: 'Прочее', kind: CategoryKind.income));

        expect(await repo.findById('b'), isNotNull);
      });

      test('the same name is fine on another level or under another '
          'parent', () async {
        await repo.create(top('p1', name: 'Транспорт'));
        await repo.create(top('p2', name: 'Дом'));
        await repo.create(sub('s1', 'p1', 'Такси'));
        // Верхний уровень и подкатегория.
        await repo.create(top('t', name: 'Такси'));
        // Другой родитель.
        await repo.create(sub('s2', 'p2', 'Такси'));
        // Тот же родитель: дубль.
        await expectLater(repo.create(sub('s3', 'p1', 'ТАКСИ')), isDuplicate());
      });

      test('an archived category does not block the name', () async {
        await repo.create(top('a', name: 'Такси'));
        await repo.archive('a');

        await repo.create(top('b', name: 'Такси'));

        expect(await repo.findById('b'), isNotNull);
      });

      test('a deleted category does not block the name', () async {
        await rawInsert('gone', name: 'Такси', deletedAt: 5);

        await repo.create(top('b', name: 'Такси'));

        expect(await repo.findById('b'), isNotNull);
      });

      test('rename rejects a taken name and changes nothing', () async {
        await repo.create(top('a', name: 'Такси'));
        await repo.create(top('b', name: 'Метро', sortOrder: 1));
        final before = await allRows();

        await expectLater(repo.rename('b', 'такси'), isDuplicate());

        expect(await allRows(), before);
        expect((await repo.findById('b'))!.name, 'Метро');
      });

      test('rename to the own name in another case is allowed', () async {
        await repo.create(top('a', name: 'Такси'));

        await repo.rename('a', ' ТАКСИ ');

        expect((await repo.findById('a'))!.name, 'ТАКСИ');
      });

      test('rename is checked for subcategories on the same level', () async {
        await repo.create(top('p', name: 'Транспорт'));
        await repo.create(sub('s1', 'p', 'Такси'));
        await repo.create(sub('s2', 'p', 'Метро'));

        await expectLater(repo.rename('s2', 'такси'), isDuplicate());
        await repo.rename('s2', 'Транспорт'); // верхний уровень не мешает
      });

      test('restore is rejected while the name is taken', () async {
        await repo.create(top('a', name: 'Такси'));
        await repo.archive('a');
        await repo.create(top('b', name: 'Такси', sortOrder: 1));
        final before = await allRows();

        await expectLater(repo.restore('a'), isDuplicate());

        expect(await allRows(), before);
        expect((await repo.findById('a'))!.isArchived, isTrue);
      });

      test('restore works after the other category is renamed', () async {
        await repo.create(top('a', name: 'Такси'));
        await repo.archive('a');
        await repo.create(top('b', name: 'Такси', sortOrder: 1));
        await repo.rename('b', 'Метро');

        await repo.restore('a');

        expect((await repo.findById('a'))!.isArchived, isFalse);
      });
    });

    group('findById', () {
      test('returns null for a missing id', () async {
        expect(await repo.findById('missing'), isNull);
      });

      test('returns null for a soft-deleted row', () async {
        await rawInsert('gone', deletedAt: 5);

        expect(await repo.findById('gone'), isNull);
      });

      test('returns the entity with all fields', () async {
        await repo.create(top('p', kind: CategoryKind.income, sortOrder: 3));
        await repo.create(
          Category(
            id: 's',
            kind: CategoryKind.income,
            name: 'Bonus',
            iconKey: 'star',
            parentId: 'p',
            sortOrder: 2,
          ),
        );

        expect(
          await repo.findById('s'),
          Category(
            id: 's',
            kind: CategoryKind.income,
            name: 'Bonus',
            iconKey: 'star',
            parentId: 'p',
            sortOrder: 2,
          ),
        );
      });
    });

    group('timestamps', () {
      test('updated_at changes on every change, created_at never', () async {
        await repo.create(top('a'));
        final created = clock.now().millisecondsSinceEpoch;

        clock.advance(const Duration(minutes: 1));
        await repo.rename('a', 'B');
        final afterRename = await rowOf('a');
        expect(afterRename.createdAt, created);
        expect(afterRename.updatedAt, clock.now().millisecondsSinceEpoch);

        clock.advance(const Duration(minutes: 1));
        await repo.archive('a');
        final afterArchive = await rowOf('a');
        expect(afterArchive.createdAt, created);
        expect(afterArchive.updatedAt, clock.now().millisecondsSinceEpoch);
        expect(afterArchive.archivedAt, clock.now().millisecondsSinceEpoch);

        clock.advance(const Duration(minutes: 1));
        await repo.restore('a');
        final afterRestore = await rowOf('a');
        expect(afterRestore.createdAt, created);
        expect(afterRestore.updatedAt, clock.now().millisecondsSinceEpoch);
        expect(afterRestore.archivedAt, isNull);
      });
    });

    group('nextSortOrder', () {
      test('an empty kind gives 0', () async {
        await repo.create(top('inc', kind: CategoryKind.income, sortOrder: 7));
        expect(await repo.nextSortOrder(CategoryKind.expense), 0);
      });

      test('is max + 1 over top-level rows of the kind, archived included, '
          'subcategories and deleted rows ignored', () async {
        await repo.create(top('a'));
        await repo.create(top('b', sortOrder: 4));
        await repo.create(top('c', sortOrder: 2));
        await repo.archive('b');
        await repo.create(child('sub', 'a', sortOrder: 30));
        await rawInsert('gone', name: 'Gone', sortOrder: 50, deletedAt: 5);
        await repo.create(top('inc', kind: CategoryKind.income, sortOrder: 9));

        expect(await repo.nextSortOrder(CategoryKind.expense), 5);
        expect(await repo.nextSortOrder(CategoryKind.income), 10);
      });

      test('a corrupted neighbour row does not get in the way', () async {
        await repo.create(top('a', sortOrder: 3));
        await rawInsert('bad', name: '', sortOrder: 6);

        expect(await repo.nextSortOrder(CategoryKind.expense), 7);
      });

      test(
        'with parentId: max + 1 over that parent\'s subcategories, '
        'archived included, other parents and deleted rows ignored',
        () async {
          await repo.create(top('p1', sortOrder: 40));
          await repo.create(top('p2', sortOrder: 41));
          await repo.create(top('p3'));
          await repo.create(child('a', 'p1'));
          await repo.create(child('b', 'p1', sortOrder: 3));
          await repo.archive('b');
          await repo.create(child('other', 'p2', sortOrder: 20));
          await rawInsert('gone', parentId: 'p1', sortOrder: 50, deletedAt: 5);

          expect(
            await repo.nextSortOrder(CategoryKind.expense, parentId: 'p1'),
            4,
          );
          expect(
            await repo.nextSortOrder(CategoryKind.expense, parentId: 'p2'),
            21,
          );
          // Родитель без подкатегорий: с нуля, а не по номерам категорий.
          expect(
            await repo.nextSortOrder(CategoryKind.expense, parentId: 'p3'),
            0,
          );
          // Без parentId номера подкатегорий не мешают.
          expect(await repo.nextSortOrder(CategoryKind.expense), 42);
        },
      );
    });

    group('corrupted data', () {
      final variants = <String, Future<void> Function(String id)>{};

      void variant(String label, Future<void> Function(String id) insert) {
        variants[label] = insert;
      }

      variant('empty name', (id) => rawInsert(id, name: ''));
      variant('blank name', (id) => rawInsert(id, name: '   '));
      variant('name longer than 40', (id) => rawInsert(id, name: 'x' * 41));
      variant('negative sort order', (id) => rawInsert(id, sortOrder: -1));
      variant('blank icon key', (id) => rawInsert(id, iconKey: '   '));

      for (final entry in variants.entries) {
        test('${entry.key}: findById throws DataCorruptedException', () async {
          await entry.value('bad-row');

          await expectLater(
            repo.findById('bad-row'),
            throwsA(
              isA<DataCorruptedException>()
                  .having((e) => e.message, 'message', contains('bad-row'))
                  .having(
                    (e) => e.cause,
                    'cause',
                    isA<CategoryRuleException>(),
                  ),
            ),
          );
        });

        test('${entry.key}: the stream gets a DataCorruptedException '
            'event', () async {
          await entry.value('bad-row');

          await expectLater(
            repo.watchTopLevel(CategoryKind.expense),
            emitsError(
              isA<DataCorruptedException>().having(
                (e) => e.message,
                'message',
                contains('bad-row'),
              ),
            ),
          );
        });
      }

      test('a corrupted subcategory reaches watchSubcategories as an error '
          'event', () async {
        await repo.create(top('p'));
        await rawInsert('bad-sub', parentId: 'p', name: '');

        await expectLater(
          repo.watchSubcategories('p'),
          emitsError(isA<DataCorruptedException>()),
        );
      });

      for (final entry in {
        'empty name': '',
        'blank name': '   ',
        'name longer than 40': 'x' * 41,
      }.entries) {
        test('rename repairs a corrupted row (${entry.key}): it reads fine '
            'afterwards', () async {
          await rawInsert('bad-row', name: entry.value);
          await expectLater(
            repo.findById('bad-row'),
            throwsA(isA<DataCorruptedException>()),
          );

          clock.advance(const Duration(minutes: 1));
          await repo.rename('bad-row', '  Fine ');

          final found = await repo.findById('bad-row');
          expect(found!.name, 'Fine');
          expect(
            (await rowOf('bad-row')).updatedAt,
            clock.now().millisecondsSinceEpoch,
          );
        });
      }

      test('rename with a bad name on a corrupted row is a rule error and '
          'the row stays as it was', () async {
        await rawInsert('bad-row', name: '');
        final before = await rowOf('bad-row');

        await expectLater(
          repo.rename('bad-row', '  '),
          throwsA(
            isA<CategoryRuleException>().having(
              (e) => e.rule,
              'rule',
              CategoryRule.emptyName,
            ),
          ),
        );
        await expectLater(
          repo.rename('bad-row', 'x' * 41),
          throwsA(
            isA<CategoryRuleException>().having(
              (e) => e.rule,
              'rule',
              CategoryRule.nameTooLong,
            ),
          ),
        );

        expect(await rowOf('bad-row'), before);
      });

      test(
        'rename of a row corrupted in another field does not read it',
        () async {
          // Пустой ключ иконки чинится не переименованием, но и не мешает ему.
          await rawInsert('bad-row', iconKey: '   ');

          await repo.rename('bad-row', 'Fine');

          expect((await rowOf('bad-row')).name, 'Fine');
        },
      );

      Matcher duplicateName() => throwsA(
        isA<CategoryRuleException>().having(
          (e) => e.rule,
          'rule',
          CategoryRule.duplicateName,
        ),
      );

      // Испорченный сосед того же вида и уровня не должен мешать create,
      // rename и restore: имена сравниваются по сырым строкам.
      for (final entry in variants.entries) {
        group('corrupted neighbour (${entry.key})', () {
          test('create without a duplicate works', () async {
            await entry.value('bad-row');

            await repo.create(top('a', name: 'Fine'));

            expect((await rowOf('a')).name, 'Fine');
          });

          test('create with a duplicate is duplicateName, whatever the row '
              'order', () async {
            // Плохая строка добавлена до и после хорошей: результат один.
            await entry.value('bad-before');
            await repo.create(top('good', name: 'Dup'));
            await entry.value('bad-after');

            await expectLater(
              repo.create(top('x', name: ' dup ')),
              duplicateName(),
            );
          });

          test('rename without a duplicate works', () async {
            await repo.create(top('a', name: 'A'));
            await entry.value('bad-row');

            await repo.rename('a', 'B');

            expect((await rowOf('a')).name, 'B');
          });

          test('rename to a duplicate is duplicateName', () async {
            await entry.value('bad-before');
            await repo.create(top('good', name: 'Dup'));
            await repo.create(top('a', name: 'A'));
            await entry.value('bad-after');

            await expectLater(repo.rename('a', 'DUP'), duplicateName());
            expect((await rowOf('a')).name, 'A');
          });

          test('restore without a duplicate works', () async {
            await repo.create(top('a', name: 'A'));
            await repo.archive('a');
            await entry.value('bad-row');

            await repo.restore('a');

            expect((await rowOf('a')).archivedAt, isNull);
          });

          test('restore with a duplicate is duplicateName', () async {
            await repo.create(top('a', name: 'Dup'));
            await repo.archive('a');
            await entry.value('bad-before');
            await repo.create(top('good', name: 'dup'));
            await entry.value('bad-after');

            await expectLater(repo.restore('a'), duplicateName());
            expect((await rowOf('a')).archivedAt, isNotNull);
          });
        });
      }
    });

    group('hasAny', () {
      test('is false on an empty database', () async {
        expect(await repo.hasAny(), isFalse);
      });

      test('is true after create', () async {
        await repo.create(top('a'));

        expect(await repo.hasAny(), isTrue);
      });

      test('is true when the only category is archived', () async {
        await repo.create(top('a'));
        await repo.archive('a');

        expect(await repo.hasAny(), isTrue);
      });

      test('is true when the only category is soft-deleted', () async {
        await rawInsert('gone', deletedAt: 5);

        expect(await repo.hasAny(), isTrue);
      });
    });
  });
}
