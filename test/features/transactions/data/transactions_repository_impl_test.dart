import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/errors/data_corrupted_exception.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/categories/data/categories_repository_impl.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/fixed_clock.dart';

/// Записывает всё, что приходит из потока: значения и ошибки. Тест сначала
/// ждёт текущее состояние, потом пишет и проверяет, что поток сам прислал
/// новое событие.
final class _Recorder<T> {
  _Recorder(Stream<T> stream) {
    _subscription = stream.listen(events.add, onError: errors.add);
  }

  final List<T> events = [];
  final List<Object> errors = [];
  late final StreamSubscription<T> _subscription;

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

  /// Ждёт, пока придёт не меньше [count] ошибок (до ~2 секунд).
  Future<void> waitForErrors(int count) async {
    for (var i = 0; i < 2000 && errors.length < count; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    expect(
      errors.length,
      greaterThanOrEqualTo(count),
      reason: 'the stream did not deliver $count errors (events: $events)',
    );
  }

  /// Даёт потоку время прислать лишние события, если они есть.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 30));

  Future<void> cancel() => _subscription.cancel();
}

void main() {
  group('DriftTransactionsRepository', () {
    late AppDatabase db;
    late FixedClock clock;
    late DriftTransactionsRepository repo;
    late DriftCategoriesRepository categories;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      clock = FixedClock(DateTime.utc(2026, 9, 20, 12));
      repo = DriftTransactionsRepository(db, clock: clock);

      // Категории для проверки связей: расходные 'cat' (с подкатегориями
      // 'sub' и 'sub2') и 'cat2', доходная 'inc' (с подкатегорией 'incsub').
      categories = DriftCategoriesRepository(db, clock: clock);
      await categories.create(
        Category.topLevel(
          id: 'cat',
          kind: CategoryKind.expense,
          name: 'Food',
          iconKey: 'icon',
          sortOrder: 0,
        ),
      );
      await categories.create(
        Category.topLevel(
          id: 'cat2',
          kind: CategoryKind.expense,
          name: 'Transport',
          iconKey: 'icon',
          sortOrder: 1,
        ),
      );
      await categories.create(
        Category(
          id: 'sub',
          kind: CategoryKind.expense,
          name: 'Bread',
          iconKey: 'icon',
          parentId: 'cat',
          sortOrder: 0,
        ),
      );
      await categories.create(
        Category(
          id: 'sub2',
          kind: CategoryKind.expense,
          name: 'Milk',
          iconKey: 'icon',
          parentId: 'cat',
          sortOrder: 1,
        ),
      );
      await categories.create(
        Category.topLevel(
          id: 'inc',
          kind: CategoryKind.income,
          name: 'Salary',
          iconKey: 'icon',
          sortOrder: 0,
        ),
      );
      await categories.create(
        Category(
          id: 'incsub',
          kind: CategoryKind.income,
          name: 'Bonus',
          iconKey: 'icon',
          parentId: 'inc',
          sortOrder: 0,
        ),
      );
    });

    tearDown(() async {
      await db.close();
    });

    Transaction tx(
      String id, {
      TransactionType type = TransactionType.expense,
      int amountMinor = 100,
      String currency = 'RUB',
      DateOnly? day,
      DateTime? at,
      String? categoryId,
      String? subcategoryId,
      String? note,
    }) {
      final onDay = day ?? DateOnly(2026, 9, 20);
      return Transaction(
        id: id,
        type: type,
        amount: Money.fromMinor(amountMinor, currency),
        occurredOn: onDay,
        occurredAt: at ?? DateTime.utc(onDay.year, onDay.month, onDay.day, 10),
        // По умолчанию категория подходит типу: 'cat' для расхода и 'inc'
        // для дохода.
        categoryId:
            categoryId ?? (type == TransactionType.income ? 'inc' : 'cat'),
        subcategoryId: subcategoryId,
        note: note,
      );
    }

    Future<TransactionRow> rowOf(String id) async {
      final rows = await db.select(db.transactions).get();
      return rows.firstWhere((r) => r.id == id);
    }

    /// Строка «в обход» репозитория, в том числе испорченная.
    Future<void> rawInsert(
      String id, {
      int occurredOn = 20260920,
      int occurredAt = 1000,
      int amountMinor = 100,
      String categoryId = 'cat',
    }) {
      return db.customStatement(
        'INSERT INTO transactions (id, type, amount_minor, currency, '
        'occurred_on, occurred_at, category_id, subcategory_id, note, '
        'created_at, updated_at, deleted_at) '
        "VALUES (?, 'expense', ?, 'RUB', ?, ?, ?, NULL, NULL, 1, 1, NULL)",
        [id, amountMinor, occurredOn, occurredAt, categoryId],
      );
    }

    Future<List<String>> recentIds({int limit = 50}) async {
      final list = await repo.watchRecent(limit: limit).first;
      return list.map((t) => t.id).toList();
    }

    Future<_Recorder<T>> record<T>(Stream<T> stream) async {
      final recorder = _Recorder<T>(stream);
      addTearDown(recorder.cancel);
      return recorder;
    }

    Future<_Recorder<List<Transaction>>> recordRecent() async {
      final recorder = await record(repo.watchRecent());
      await recorder.waitForEvents(1); // текущее состояние
      return recorder;
    }

    List<List<String>> idsOf(_Recorder<List<Transaction>> rec) =>
        rec.events.map((list) => list.map((t) => t.id).toList()).toList();

    group('add and findById', () {
      test('round trip keeps all fields', () async {
        final original = tx(
          'a',
          type: TransactionType.income,
          amountMinor: 12345,
          currency: 'USD',
          day: DateOnly(2026, 3, 7),
          at: DateTime.utc(2026, 3, 7, 21, 30, 15, 123),
          categoryId: 'inc',
          subcategoryId: 'incsub',
          note: 'Coffee and bread',
        );

        await repo.add(original);
        final found = await repo.findById('a');

        expect(found, original);
        expect(found!.occurredAt.isUtc, isTrue);
        expect(found.occurredAt, DateTime.utc(2026, 3, 7, 21, 30, 15, 123));
        expect(found.amount, Money.fromMinor(12345, 'USD'));
        expect(found.type, TransactionType.income);
        expect(found.occurredOn, DateOnly(2026, 3, 7));
      });

      test('round trip keeps null variants and a zero amount', () async {
        final original = tx('a', amountMinor: 0);

        await repo.add(original);
        final found = await repo.findById('a');

        expect(found, original);
        expect(found!.subcategoryId, isNull);
        expect(found.note, isNull);
        expect(found.amount.isZero, isTrue);
      });

      test('a note is stored trimmed', () async {
        await repo.add(tx('a', note: '  hello  '));

        expect((await repo.findById('a'))!.note, 'hello');
      });

      test('writes the expected raw columns', () async {
        await repo.add(
          tx(
            'a',
            amountMinor: 250,
            day: DateOnly(2026, 3, 7),
            at: DateTime.utc(2026, 3, 7, 21),
            note: 'n',
          ),
        );

        final row = await rowOf('a');
        final now = clock.now().millisecondsSinceEpoch;
        expect(row.type, TransactionType.expense);
        expect(row.amountMinor, 250);
        expect(row.currency, 'RUB');
        expect(row.occurredOn, DateOnly(2026, 3, 7));
        expect(
          row.occurredAt,
          DateTime.utc(2026, 3, 7, 21).millisecondsSinceEpoch,
        );
        expect(row.categoryId, 'cat');
        expect(row.subcategoryId, isNull);
        expect(row.note, 'n');
        expect(row.createdAt, now);
        expect(row.updatedAt, now);
        expect(row.deletedAt, isNull);
      });

      test('findById returns null for a missing id', () async {
        expect(await repo.findById('missing'), isNull);
      });

      test('a repeated id is not wrapped: the database error comes out and '
          'the first row stays', () async {
        await repo.add(tx('a', amountMinor: 1));

        await expectLater(
          repo.add(tx('a', amountMinor: 2)),
          throwsA(
            predicate<Object>(
              (e) => e.toString().contains('UNIQUE constraint failed'),
            ),
          ),
        );
        expect((await repo.findById('a'))!.amount.minorUnits, 1);
      });
    });

    /// Категория «в обход» репозитория (в том числе такая, какую он сам не
    /// создал бы: подкатегория другого вида, испорченный вид, удалённая).
    Future<void> rawCategory(
      String id, {
      String kind = 'expense',
      String? parentId,
      int? archivedAt,
      int? deletedAt,
    }) {
      return db.customStatement(
        'INSERT INTO categories (id, kind, name, icon_key, parent_id, '
        'sort_order, archived_at, created_at, updated_at, deleted_at) '
        "VALUES (?, ?, 'Raw', 'icon', ?, 9, ?, 1, 1, ?)",
        [id, kind, parentId, archivedAt, deletedAt],
      );
    }

    Matcher throwsRule(TransactionRule rule) => throwsA(
      isA<TransactionRuleException>().having((e) => e.rule, 'rule', rule),
    );

    Future<int> rowCount() async =>
        (await db.select(db.transactions).get()).length;

    group('links to categories (second line of defence)', () {
      test('an expense in an income category is typeKindMismatch and nothing '
          'is stored', () async {
        await expectLater(
          repo.add(tx('a', categoryId: 'inc')),
          throwsRule(TransactionRule.typeKindMismatch),
        );

        expect(await rowCount(), 0);
      });

      test('an income in an expense category is typeKindMismatch', () async {
        await expectLater(
          repo.add(tx('a', type: TransactionType.income, categoryId: 'cat')),
          throwsRule(TransactionRule.typeKindMismatch),
        );
        expect(await rowCount(), 0);
      });

      test(
        'a subcategory of another category is subcategoryNotOfCategory',
        () async {
          await expectLater(
            repo.add(tx('a', categoryId: 'cat2', subcategoryId: 'sub')),
            throwsRule(TransactionRule.subcategoryNotOfCategory),
          );
          expect(await rowCount(), 0);
        },
      );

      test('a top-level category as the subcategory is '
          'subcategoryNotOfCategory', () async {
        await expectLater(
          repo.add(tx('a', categoryId: 'cat', subcategoryId: 'cat2')),
          throwsRule(TransactionRule.subcategoryNotOfCategory),
        );
      });

      test('a subcategory as the category is categoryMustBeTopLevel', () async {
        await expectLater(
          repo.add(tx('a', categoryId: 'sub')),
          throwsRule(TransactionRule.categoryMustBeTopLevel),
        );
        expect(await rowCount(), 0);
      });

      test('a subcategory of another kind under the right parent is '
          'typeKindMismatch', () async {
        // Такую строку репозиторий категорий не создал бы (kindMismatch),
        // но испорченная база может её содержать.
        await rawCategory('badkind', kind: 'income', parentId: 'cat');

        await expectLater(
          repo.add(tx('a', categoryId: 'cat', subcategoryId: 'badkind')),
          throwsRule(TransactionRule.typeKindMismatch),
        );
        expect(await rowCount(), 0);
      });

      test('a missing category is an ArgumentError with the id, not a SQLite '
          'error', () async {
        Object? caught;
        try {
          await repo.add(tx('a', categoryId: 'nope'));
        } catch (error) {
          caught = error;
        }

        expect(caught, isA<ArgumentError>());
        expect((caught! as ArgumentError).invalidValue, 'nope');
        expect(await rowCount(), 0);
      });

      test('a missing subcategory is an ArgumentError', () async {
        await expectLater(
          repo.add(tx('a', subcategoryId: 'nope')),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.invalidValue,
              'invalidValue',
              'nope',
            ),
          ),
        );
        expect(await rowCount(), 0);
      });

      test('soft-deleted categories count as missing', () async {
        await rawCategory('gone', deletedAt: 5);
        await rawCategory('gone-sub', parentId: 'cat', deletedAt: 5);

        await expectLater(
          repo.add(tx('a', categoryId: 'gone')),
          throwsArgumentError,
        );
        await expectLater(
          repo.add(tx('b', subcategoryId: 'gone-sub')),
          throwsArgumentError,
        );
        expect(await rowCount(), 0);
      });

      test('the database foreign key is still the last barrier for a raw '
          'insert', () async {
        await expectLater(
          rawInsert('a', categoryId: 'nope'),
          throwsA(
            predicate<Object>(
              (e) => e.toString().contains('FOREIGN KEY constraint failed'),
            ),
          ),
        );
      });

      test('a corrupted category kind is DataCorruptedException', () async {
        // CHECK схемы не даёт записать такой вид; на время вставки его
        // выключаем, как это сделала бы испорченная база.
        await db.customStatement('PRAGMA ignore_check_constraints = ON');
        await rawCategory('weird', kind: 'other');
        await db.customStatement('PRAGMA ignore_check_constraints = OFF');

        await expectLater(
          repo.add(tx('a', categoryId: 'weird')),
          throwsA(
            isA<DataCorruptedException>().having(
              (e) => e.message,
              'message',
              contains('weird'),
            ),
          ),
        );
        expect(await rowCount(), 0);
      });

      test('a valid category with a subcategory is stored', () async {
        await repo.add(tx('a', subcategoryId: 'sub'));

        expect((await repo.findById('a'))!.subcategoryId, 'sub');
      });

      group('archived categories', () {
        test('add in an archived category is categoryArchived', () async {
          await categories.archive('cat2');

          await expectLater(
            repo.add(tx('a', categoryId: 'cat2')),
            throwsRule(TransactionRule.categoryArchived),
          );
          expect(await rowCount(), 0);
        });

        test('add in an archived subcategory is categoryArchived', () async {
          await categories.archive('sub');

          await expectLater(
            repo.add(tx('a', subcategoryId: 'sub')),
            throwsRule(TransactionRule.categoryArchived),
          );
          // Соседняя живая подкатегория той же категории по-прежнему годится.
          await repo.add(tx('b', subcategoryId: 'sub2'));
          expect(await rowCount(), 1);
        });

        test('restore makes the category usable again', () async {
          await categories.archive('cat2');
          await categories.restore('cat2');

          await repo.add(tx('a', categoryId: 'cat2'));

          expect(await rowCount(), 1);
        });

        test('update to an archived category is categoryArchived and keeps '
            'the old row', () async {
          await repo.add(tx('a'));
          await categories.archive('cat2');
          final before = await rowOf('a');

          await expectLater(
            repo.update(tx('a', categoryId: 'cat2')),
            throwsRule(TransactionRule.categoryArchived),
          );

          expect(await rowOf('a'), before);
        });

        test('update to an archived subcategory is categoryArchived', () async {
          await repo.add(tx('a', subcategoryId: 'sub'));
          await categories.archive('sub2');

          await expectLater(
            repo.update(tx('a', subcategoryId: 'sub2')),
            throwsRule(TransactionRule.categoryArchived),
          );
          expect((await repo.findById('a'))!.subcategoryId, 'sub');
        });

        test('update that stays in the now archived category may change the '
            'amount and the note', () async {
          await repo.add(tx('a', subcategoryId: 'sub', amountMinor: 100));
          await categories.archive('cat');
          await categories.archive('sub');

          await repo.update(
            tx('a', subcategoryId: 'sub', amountMinor: 250, note: 'fixed'),
          );

          final found = await repo.findById('a');
          expect(found!.amount.minorUnits, 250);
          expect(found.note, 'fixed');
          expect(found.categoryId, 'cat');
          expect(found.subcategoryId, 'sub');
        });

        test('update may drop the archived subcategory', () async {
          await repo.add(tx('a', subcategoryId: 'sub'));
          await categories.archive('sub');

          await repo.update(tx('a'));

          expect((await repo.findById('a'))!.subcategoryId, isNull);
        });

        test('update may add a live subcategory under an unchanged archived '
            'category', () async {
          await repo.add(tx('a', amountMinor: 1));
          await categories.archive('cat');

          // Категория та же (архивная) и не менялась, подкатегория новая и
          // живая: разрешено.
          await repo.update(tx('a', subcategoryId: 'sub'));

          expect((await repo.findById('a'))!.subcategoryId, 'sub');
        });
      });

      group('update', () {
        test('to a missing category is an ArgumentError and keeps the old '
            'row', () async {
          await repo.add(tx('a'));

          await expectLater(
            repo.update(tx('a', categoryId: 'nope')),
            throwsArgumentError,
          );
          expect((await repo.findById('a'))!.categoryId, 'cat');
        });

        test('to a category of another kind is typeKindMismatch', () async {
          await repo.add(tx('a'));

          await expectLater(
            repo.update(tx('a', categoryId: 'inc')),
            throwsRule(TransactionRule.typeKindMismatch),
          );
          expect((await repo.findById('a'))!.categoryId, 'cat');
        });

        test(
          'changing the type with a new category of the new kind works',
          () async {
            await repo.add(tx('a', subcategoryId: 'sub'));

            await repo.update(
              tx('a', type: TransactionType.income, categoryId: 'inc'),
            );

            final found = await repo.findById('a');
            expect(found!.type, TransactionType.income);
            expect(found.categoryId, 'inc');
            expect(found.subcategoryId, isNull);
          },
        );

        test('changing the type but keeping the old category is '
            'typeKindMismatch', () async {
          await repo.add(tx('a'));

          await expectLater(
            repo.update(
              tx('a', type: TransactionType.income, categoryId: 'cat'),
            ),
            throwsRule(TransactionRule.typeKindMismatch),
          );
          expect((await repo.findById('a'))!.type, TransactionType.expense);
        });

        test('a subcategory of another category is '
            'subcategoryNotOfCategory', () async {
          await repo.add(tx('a'));

          await expectLater(
            repo.update(tx('a', categoryId: 'cat2', subcategoryId: 'sub')),
            throwsRule(TransactionRule.subcategoryNotOfCategory),
          );
        });

        test(
          'a subcategory as the category is categoryMustBeTopLevel',
          () async {
            await repo.add(tx('a'));

            await expectLater(
              repo.update(tx('a', categoryId: 'sub')),
              throwsRule(TransactionRule.categoryMustBeTopLevel),
            );
          },
        );

        test('staying in an archived category still requires a matching '
            'type', () async {
          // Архивность не проверяется, но вид категории и тип — да.
          await repo.add(tx('a'));
          await categories.archive('cat');

          await expectLater(
            repo.update(
              tx('a', type: TransactionType.income, categoryId: 'cat'),
            ),
            throwsRule(TransactionRule.typeKindMismatch),
          );
        });
      });
    });

    group('update', () {
      test('changes all fields and updated_at, created_at stays', () async {
        await repo.add(tx('a', subcategoryId: 'sub', note: 'old'));
        final created = clock.now().millisecondsSinceEpoch;
        clock.advance(const Duration(minutes: 5));

        final changed = tx(
          'a',
          type: TransactionType.income,
          amountMinor: 777,
          currency: 'EUR',
          day: DateOnly(2026, 1, 2),
          at: DateTime.utc(2026, 1, 2, 3, 4, 5, 6),
          categoryId: 'inc',
          note: 'new',
        );
        await repo.update(changed);

        expect(await repo.findById('a'), changed);
        final row = await rowOf('a');
        expect(row.createdAt, created);
        expect(row.updatedAt, clock.now().millisecondsSinceEpoch);
        expect(row.deletedAt, isNull);
      });

      test('null subcategory and note clear the stored values', () async {
        await repo.add(tx('a', subcategoryId: 'sub', note: 'old'));

        await repo.update(tx('a'));

        final found = await repo.findById('a');
        expect(found!.subcategoryId, isNull);
        expect(found.note, isNull);
      });

      test('does not touch other rows', () async {
        await repo.add(tx('a', amountMinor: 1));
        await repo.add(tx('b', amountMinor: 2));

        await repo.update(tx('a', amountMinor: 10));

        expect((await repo.findById('b'))!.amount.minorUnits, 2);
      });

      test('a missing transaction is an ArgumentError', () async {
        await expectLater(repo.update(tx('missing')), throwsArgumentError);
        expect(await repo.findById('missing'), isNull);
      });

      test('a soft-deleted transaction is an ArgumentError and stays '
          'unchanged', () async {
        await repo.add(tx('a', amountMinor: 1));
        await repo.softDelete('a');
        final before = await rowOf('a');

        await expectLater(
          repo.update(tx('a', amountMinor: 999)),
          throwsArgumentError,
        );

        expect(await rowOf('a'), before);
      });
    });

    group('softDelete and restore', () {
      test(
        'softDelete removes the row from findById and watchRecent',
        () async {
          await repo.add(tx('a'));
          await repo.add(tx('b', day: DateOnly(2026, 9, 19)));

          await repo.softDelete('a');

          expect(await repo.findById('a'), isNull);
          expect(await recentIds(), ['b']);
          // Строка физически остаётся.
          expect((await rowOf('a')).deletedAt, isNotNull);
        },
      );

      test('softDelete writes deleted_at = updated_at = now', () async {
        await repo.add(tx('a'));
        final created = clock.now().millisecondsSinceEpoch;
        clock.advance(const Duration(minutes: 3));

        await repo.softDelete('a');

        final row = await rowOf('a');
        final now = clock.now().millisecondsSinceEpoch;
        expect(row.deletedAt, now);
        expect(row.updatedAt, now);
        expect(row.createdAt, created);
      });

      test('restore brings the transaction back with all its fields', () async {
        final original = tx(
          'a',
          type: TransactionType.income,
          amountMinor: 4200,
          currency: 'USD',
          day: DateOnly(2026, 3, 7),
          at: DateTime.utc(2026, 3, 7, 21, 30, 15, 123),
          subcategoryId: 'incsub',
          note: 'Coffee',
        );
        await repo.add(original);
        final created = clock.now().millisecondsSinceEpoch;
        await repo.softDelete('a');
        clock.advance(const Duration(minutes: 3));

        await repo.restore('a');

        expect(await repo.findById('a'), original);
        expect(await recentIds(), ['a']);
        final row = await rowOf('a');
        expect(row.deletedAt, isNull);
        expect(row.updatedAt, clock.now().millisecondsSinceEpoch);
        expect(row.createdAt, created);
      });

      test('a repeated softDelete changes nothing', () async {
        await repo.add(tx('a'));
        clock.advance(const Duration(minutes: 1));
        await repo.softDelete('a');
        final before = await rowOf('a');

        clock.advance(const Duration(minutes: 10));
        await repo.softDelete('a');

        expect(await rowOf('a'), before);
      });

      test('restore of a live transaction changes nothing', () async {
        await repo.add(tx('a'));
        final before = await rowOf('a');

        clock.advance(const Duration(minutes: 10));
        await repo.restore('a');

        expect(await rowOf('a'), before);
      });

      test('a missing id is an ArgumentError for both', () async {
        await expectLater(repo.softDelete('missing'), throwsArgumentError);
        await expectLater(repo.restore('missing'), throwsArgumentError);
      });
    });

    group('findAllLive (для экспорта)', () {
      test(
        'возвращает все живые операции без ограничения по количеству',
        () async {
          for (var i = 0; i < 55; i++) {
            await rawInsert('t$i');
          }
          final all = await repo.findAllLive();
          expect(all, hasLength(55));
        },
      );

      test('мягко удалённые операции не попадают', () async {
        await repo.add(tx('live'));
        await repo.add(tx('gone'));
        await repo.softDelete('gone');
        final all = await repo.findAllLive();
        expect(all.map((t) => t.id), ['live']);
      });

      test('операции в архивной категории попадают', () async {
        await repo.add(tx('kept', categoryId: 'cat2'));
        await categories.archive('cat2');
        final all = await repo.findAllLive();
        expect(all.map((t) => t.id), ['kept']);
      });

      test(
        'испорченная строка даёт DataCorruptedException, а не пропуск',
        () async {
          await rawInsert('bad', occurredOn: 20261332);
          await repo.add(tx('fine'));
          await expectLater(
            repo.findAllLive(),
            throwsA(isA<DataCorruptedException>()),
          );
        },
      );
    });

    group('watchRecent order and limit', () {
      test('newer days come first', () async {
        await repo.add(tx('d1', day: DateOnly(2026, 9, 1)));
        await repo.add(tx('d3', day: DateOnly(2026, 9, 3)));
        await repo.add(tx('d2', day: DateOnly(2026, 9, 2)));

        expect(await recentIds(), ['d3', 'd2', 'd1']);
      });

      test('within one day a later time comes first', () async {
        final day = DateOnly(2026, 9, 5);
        await repo.add(tx('t10', day: day, at: DateTime.utc(2026, 9, 5, 10)));
        await repo.add(tx('t09', day: day, at: DateTime.utc(2026, 9, 5, 9)));
        await repo.add(tx('t11', day: day, at: DateTime.utc(2026, 9, 5, 11)));

        expect(await recentIds(), ['t11', 't10', 't09']);
      });

      test('the local day decides before the moment', () async {
        // День 20 записан с более ранним моментом, чем день 19.
        await repo.add(
          tx(
            'day20',
            day: DateOnly(2026, 9, 20),
            at: DateTime.utc(2026, 9, 19, 1),
          ),
        );
        await repo.add(
          tx(
            'day19',
            day: DateOnly(2026, 9, 19),
            at: DateTime.utc(2026, 9, 19, 23),
          ),
        );

        expect(await recentIds(), ['day20', 'day19']);
      });

      test('equal day and moment are ordered by id descending', () async {
        await repo.add(tx('a'));
        await repo.add(tx('c'));
        await repo.add(tx('b'));

        expect(await recentIds(), ['c', 'b', 'a']);
      });

      test('the limit keeps only the newest rows', () async {
        for (var day = 1; day <= 5; day++) {
          await repo.add(tx('d$day', day: DateOnly(2026, 9, day)));
        }

        expect(await recentIds(limit: 2), ['d5', 'd4']);
        expect(await recentIds(limit: 50), ['d5', 'd4', 'd3', 'd2', 'd1']);
      });

      test('the default limit is 50', () async {
        for (var i = 0; i < 55; i++) {
          await repo.add(
            tx(
              't${i.toString().padLeft(2, '0')}',
              at: DateTime.utc(2026, 9, 20, 0, i),
            ),
          );
        }

        final list = await repo.watchRecent().first;

        expect(list, hasLength(50));
        expect(list.first.id, 't54');
      });

      test('a limit of zero or less is an ArgumentError at once', () {
        expect(() => repo.watchRecent(limit: 0), throwsArgumentError);
        expect(() => repo.watchRecent(limit: -1), throwsArgumentError);
      });

      test('an empty database gives an empty list', () async {
        expect(await recentIds(), isEmpty);
      });
    });

    group('watchRecent updates itself after a write', () {
      test('add', () async {
        final rec = await recordRecent();
        expect(idsOf(rec), [<String>[]]);

        await repo.add(tx('a'));
        await rec.waitForEvents(2);
        await rec.settle();

        expect(idsOf(rec), [
          <String>[],
          ['a'],
        ]);
      });

      test('update', () async {
        await repo.add(tx('a', amountMinor: 1));
        final rec = await recordRecent();

        await repo.update(tx('a', amountMinor: 2));
        await rec.waitForEvents(2);
        await rec.settle();

        expect(
          rec.events.map((l) => l.map((t) => t.amount.minorUnits).toList()),
          [
            [1],
            [2],
          ],
        );
      });

      test('softDelete and restore', () async {
        await repo.add(tx('a', day: DateOnly(2026, 9, 2)));
        await repo.add(tx('b', day: DateOnly(2026, 9, 1)));
        final rec = await recordRecent();

        await repo.softDelete('a');
        await rec.waitForEvents(2);
        await repo.restore('a');
        await rec.waitForEvents(3);
        await rec.settle();

        expect(idsOf(rec), [
          ['a', 'b'],
          ['b'],
          ['a', 'b'],
        ]);
      });
    });

    group('watchTotal', () {
      final september = monthRange(DateOnly(2026, 9, 15));

      Future<Money> total({
        TransactionType type = TransactionType.expense,
        DateRange? period,
        String currency = 'RUB',
      }) {
        return repo
            .watchTotal(
              type: type,
              period: period ?? september,
              currency: currency,
            )
            .first;
      }

      test('counts only live rows of the requested type', () async {
        await repo.add(tx('e1', amountMinor: 100));
        await repo.add(tx('e2', amountMinor: 250));
        await repo.add(
          tx('i1', type: TransactionType.income, amountMinor: 5000),
        );
        await repo.add(tx('gone', amountMinor: 9000));
        await repo.softDelete('gone');

        expect(await total(), Money.fromMinor(350, 'RUB'));
        expect(
          await total(type: TransactionType.income),
          Money.fromMinor(5000, 'RUB'),
        );
      });

      test('an empty period is zero in the requested currency', () async {
        expect(await total(), Money.zero('RUB'));
        expect(await total(currency: 'USD'), Money.zero('USD'));
        expect((await total(currency: 'USD')).currency, 'USD');
      });

      test('a zero amount adds nothing', () async {
        await repo.add(tx('z', amountMinor: 0));
        await repo.add(tx('a', amountMinor: 30));

        expect(await total(), Money.fromMinor(30, 'RUB'));
      });

      test(
        'month borders are inclusive, neighbouring days are outside',
        () async {
          await repo.add(
            tx('before', day: DateOnly(2026, 8, 31), amountMinor: 1),
          );
          await repo.add(
            tx('first', day: DateOnly(2026, 9, 1), amountMinor: 10),
          );
          await repo.add(
            tx('middle', day: DateOnly(2026, 9, 15), amountMinor: 100),
          );
          await repo.add(
            tx('last', day: DateOnly(2026, 9, 30), amountMinor: 1000),
          );
          await repo.add(
            tx('after', day: DateOnly(2026, 10, 1), amountMinor: 10000),
          );

          expect(await total(), Money.fromMinor(1110, 'RUB'));
        },
      );

      test('a one-day period counts exactly that day', () async {
        await repo.add(tx('a', day: DateOnly(2026, 9, 14), amountMinor: 1));
        await repo.add(tx('b', day: DateOnly(2026, 9, 15), amountMinor: 20));
        await repo.add(tx('c', day: DateOnly(2026, 9, 16), amountMinor: 300));

        expect(
          await total(period: dayRange(DateOnly(2026, 9, 15))),
          Money.fromMinor(20, 'RUB'),
        );
      });

      test('currencies are never mixed: RUB total excludes USD and vice '
          'versa', () async {
        await repo.add(tx('rub1', amountMinor: 100));
        await repo.add(tx('rub2', amountMinor: 50));
        await repo.add(tx('usd1', amountMinor: 7, currency: 'USD'));
        await repo.add(tx('usd2', amountMinor: 3, currency: 'USD'));

        expect(await total(), Money.fromMinor(150, 'RUB'));
        expect(await total(currency: 'USD'), Money.fromMinor(10, 'USD'));
        expect(await total(currency: 'EUR'), Money.zero('EUR'));
      });

      test('the default currency is RUB', () async {
        await repo.add(tx('rub', amountMinor: 100));
        await repo.add(tx('usd', amountMinor: 7, currency: 'USD'));

        final value = await repo
            .watchTotal(type: TransactionType.expense, period: september)
            .first;

        expect(value, Money.fromMinor(100, 'RUB'));
      });

      test('a wrong currency code is an ArgumentError at once', () {
        for (final code in ['rub', 'RU', 'RUBL', '', 'R1B']) {
          expect(
            () => repo.watchTotal(
              type: TransactionType.expense,
              period: september,
              currency: code,
            ),
            throwsArgumentError,
            reason: 'code "$code"',
          );
        }
      });

      test('the stream updates after add, update, softDelete and '
          'restore', () async {
        final rec = await record(
          repo.watchTotal(type: TransactionType.expense, period: september),
        );
        await rec.waitForEvents(1);
        expect(rec.events, [Money.zero('RUB')]);

        await repo.add(tx('a', amountMinor: 100));
        await rec.waitForEvents(2);
        await repo.update(tx('a', amountMinor: 150));
        await rec.waitForEvents(3);
        await repo.softDelete('a');
        await rec.waitForEvents(4);
        await repo.restore('a');
        await rec.waitForEvents(5);
        await rec.settle();

        expect(rec.events, [
          Money.zero('RUB'),
          Money.fromMinor(100, 'RUB'),
          Money.fromMinor(150, 'RUB'),
          Money.zero('RUB'),
          Money.fromMinor(150, 'RUB'),
        ]);
      });

      test(
        'a row of another currency does not change the total value',
        () async {
          final rec = await record(
            repo.watchTotal(type: TransactionType.expense, period: september),
          );
          await rec.waitForEvents(1);

          await repo.add(tx('usd', amountMinor: 7, currency: 'USD'));
          await rec.settle();

          expect(rec.events, everyElement(Money.zero('RUB')));
        },
      );
    });

    group('watchFirstDay', () {
      test('no operations: null', () async {
        expect(await repo.watchFirstDay().first, isNull);
      });

      test('earliest live day; soft-deleted are ignored', () async {
        await repo.add(tx('mid', day: DateOnly(2026, 9, 10)));
        await repo.add(tx('gone', day: DateOnly(2026, 3, 1)));
        await repo.softDelete('gone');

        expect(await repo.watchFirstDay().first, DateOnly(2026, 9, 10));
      });

      test('only soft-deleted operations: null', () async {
        await repo.add(tx('gone', day: DateOnly(2026, 3, 1)));
        await repo.softDelete('gone');

        expect(await repo.watchFirstDay().first, isNull);
      });

      test('stream follows add, softDelete and restore', () async {
        await repo.add(tx('mid', day: DateOnly(2026, 9, 10)));
        final rec = await record(repo.watchFirstDay());
        await rec.waitForEvents(1);
        expect(rec.events.last, DateOnly(2026, 9, 10));

        await repo.add(tx('early', day: DateOnly(2026, 2, 3)));
        await rec.waitForEvents(2);
        expect(rec.events.last, DateOnly(2026, 2, 3));

        await repo.softDelete('early');
        await rec.waitForEvents(3);
        expect(rec.events.last, DateOnly(2026, 9, 10));

        await repo.restore('early');
        await rec.waitForEvents(4);
        expect(rec.events.last, DateOnly(2026, 2, 3));
      });

      test('corrupted day is a DataCorruptedException in the stream', () async {
        await rawInsert('bad', occurredOn: 20261332);

        await expectLater(
          repo.watchFirstDay(),
          emitsError(isA<DataCorruptedException>()),
        );
      });
    });

    group('watchInPeriod', () {
      final september = monthRange(DateOnly(2026, 9, 15));

      Future<List<String>> periodIds(
        DateRange period, {
        String currency = 'RUB',
      }) async {
        final list = await repo.watchInPeriod(period, currency: currency).first;
        return list.map((t) => t.id).toList();
      }

      test('returns live rows in order: day, then moment, then id', () async {
        await repo.add(
          tx(
            'late',
            day: DateOnly(2026, 9, 5),
            at: DateTime.utc(2026, 9, 5, 18),
          ),
        );
        await repo.add(
          tx('b', day: DateOnly(2026, 9, 5), at: DateTime.utc(2026, 9, 5, 9)),
        );
        await repo.add(
          tx('a', day: DateOnly(2026, 9, 5), at: DateTime.utc(2026, 9, 5, 9)),
        );
        await repo.add(tx('first', day: DateOnly(2026, 9, 3)));

        expect(await periodIds(september), ['first', 'a', 'b', 'late']);
      });

      test('soft-deleted operations are not returned', () async {
        await repo.add(tx('kept', day: DateOnly(2026, 9, 10)));
        await repo.add(tx('gone', day: DateOnly(2026, 9, 11)));
        await repo.softDelete('gone');

        expect(await periodIds(september), ['kept']);
      });

      test(
        'both boundary days are included, the days just outside are not',
        () async {
          await repo.add(tx('before', day: DateOnly(2026, 8, 31)));
          await repo.add(tx('first', day: DateOnly(2026, 9, 1)));
          await repo.add(tx('last', day: DateOnly(2026, 9, 30)));
          await repo.add(tx('after', day: DateOnly(2026, 10, 1)));

          expect(await periodIds(september), ['first', 'last']);
        },
      );

      test('other currencies are not returned; the requested one is', () async {
        await repo.add(tx('rub', day: DateOnly(2026, 9, 10)));
        await repo.add(tx('usd', day: DateOnly(2026, 9, 10), currency: 'USD'));

        expect(await periodIds(september), ['rub']);
        expect(await periodIds(september, currency: 'USD'), ['usd']);
      });

      test('income and expense are both returned', () async {
        await repo.add(tx('exp', day: DateOnly(2026, 9, 10)));
        await repo.add(
          tx('inc', day: DateOnly(2026, 9, 10), type: TransactionType.income),
        );

        expect(await periodIds(september), ['exp', 'inc']);
      });

      test('an unknown currency code is ArgumentError at once', () {
        expect(
          () => repo.watchInPeriod(september, currency: 'rub'),
          throwsArgumentError,
        );
      });

      test(
        'a new operation in the period reaches the stream by itself',
        () async {
          final rec = await record(repo.watchInPeriod(september));
          await rec.waitForEvents(1); // текущее состояние: пусто
          expect(rec.events.last, isEmpty);

          await repo.add(tx('new', day: DateOnly(2026, 9, 12)));
          await rec.waitForEvents(2);

          expect(rec.events.last.map((t) => t.id).toList(), ['new']);
        },
      );

      test('the stream drops an operation after softDelete', () async {
        await repo.add(tx('a', day: DateOnly(2026, 9, 12)));
        await repo.add(tx('b', day: DateOnly(2026, 9, 13)));
        final rec = await record(repo.watchInPeriod(september));
        await rec.waitForEvents(1);
        expect(rec.events.last.map((t) => t.id).toList(), ['a', 'b']);

        await repo.softDelete('a');
        await rec.waitForEvents(2);

        expect(rec.events.last.map((t) => t.id).toList(), ['b']);
      });

      test('corrupted row is a DataCorruptedException in the stream', () async {
        // 20261332 — не дата; лежит внутри периода 01.12.2026-01.01.2027.
        await rawInsert('bad', occurredOn: 20261332);
        final period = DateRange(DateOnly(2026, 12, 1), DateOnly(2027, 1, 1));

        await expectLater(
          repo.watchInPeriod(period),
          emitsError(
            isA<DataCorruptedException>().having(
              (e) => e.cause,
              'cause',
              isA<FormatException>(),
            ),
          ),
        );
      });
    });

    group('corrupted data', () {
      // 20261332 проходит CHECK диапазона в схеме, но 13-го месяца нет:
      // DateOnlyConverter бросает FormatException при чтении строки.
      const badDay = 20261332;

      test(
        'findById gives DataCorruptedException, not FormatException',
        () async {
          await rawInsert('bad', occurredOn: badDay);

          await expectLater(
            repo.findById('bad'),
            throwsA(
              isA<DataCorruptedException>()
                  .having((e) => e.message, 'message', contains('bad'))
                  .having((e) => e.cause, 'cause', isA<FormatException>()),
            ),
          );
        },
      );

      test('findById of a row that fails inside the mapper: cause is the '
          'original error', () async {
        // Момент вне диапазона DateTime: конвертера нет, ошибку даёт сборка
        // сущности (ArgumentError), а её превращает transactionFromRow.
        await rawInsert('bad', occurredAt: 9223372036854775807);

        await expectLater(
          repo.findById('bad'),
          throwsA(
            isA<DataCorruptedException>()
                .having((e) => e.message, 'message', contains('bad'))
                .having((e) => e.cause, 'cause', isA<ArgumentError>()),
          ),
        );
      });

      test(
        'watchRecent sends DataCorruptedException as an error event',
        () async {
          await rawInsert('bad', occurredOn: badDay);

          await expectLater(
            repo.watchRecent(),
            emitsError(
              isA<DataCorruptedException>().having(
                (e) => e.cause,
                'cause',
                isA<FormatException>(),
              ),
            ),
          );
        },
      );

      test('the stream stays alive after the error', () async {
        await rawInsert('bad', occurredOn: badDay);
        final rec = await record(repo.watchRecent());
        await rec.waitForErrors(1);
        expect(rec.errors.single, isA<DataCorruptedException>());
        expect(rec.events, isEmpty);

        // Испорченную строку можно убрать: мягкое удаление её не читает.
        await repo.softDelete('bad');
        await rec.waitForEvents(1);

        expect(idsOf(rec), [<String>[]]);

        // И поток продолжает работать дальше.
        await repo.add(tx('good'));
        await rec.waitForEvents(2);
        await rec.settle();
        expect(idsOf(rec), [
          <String>[],
          ['good'],
        ]);
        expect(rec.errors, hasLength(1));
      });

      test('the stream stays alive after the error: an update repairs '
          'the row', () async {
        await rawInsert('bad', occurredOn: badDay);
        final rec = await record(repo.watchRecent());
        await rec.waitForErrors(1);

        await repo.update(tx('bad', amountMinor: 5));
        await rec.waitForEvents(1);

        expect(idsOf(rec), [
          ['bad'],
        ]);
      });

      test('watchTotal does not read the day: the corrupted row is summed '
          'when its number is inside the period', () async {
        await rawInsert('bad', occurredOn: badDay, amountMinor: 500);
        await repo.add(
          tx('good', day: DateOnly(2026, 12, 31), amountMinor: 20),
        );
        // 20261332 лежит между 20261231 и 20270101, поэтому берём период,
        // который включает и его.
        final period = DateRange(DateOnly(2026, 12, 1), DateOnly(2027, 1, 31));

        final inside = await repo
            .watchTotal(type: TransactionType.expense, period: period)
            .first;
        final december = await repo
            .watchTotal(
              type: TransactionType.expense,
              period: monthRange(DateOnly(2026, 12, 1)),
            )
            .first;

        expect(inside, Money.fromMinor(520, 'RUB'));
        // Обычный декабрь строку с числом 20261332 не захватывает.
        expect(december, Money.fromMinor(20, 'RUB'));
      });

      test('no public method lets FormatException out', () async {
        await rawInsert('bad', occurredOn: badDay);

        Future<Object?> outcome(Future<Object?> Function() body) async {
          try {
            return await body();
          } catch (error) {
            return error;
          }
        }

        final results = <String, Object?>{
          'findById': await outcome(() => repo.findById('bad')),
          'watchRecent': await outcome(() => repo.watchRecent().first),
          'watchInPeriod': await outcome(
            () => repo.watchInPeriod(yearRange(DateOnly(2026, 6, 1))).first,
          ),
          'watchTotal': await outcome(
            () => repo
                .watchTotal(
                  type: TransactionType.expense,
                  period: yearRange(DateOnly(2026, 6, 1)),
                )
                .first,
          ),
          'add': await outcome(() => repo.add(tx('new'))),
          'update': await outcome(() => repo.update(tx('bad'))),
          'softDelete': await outcome(() => repo.softDelete('bad')),
          'restore': await outcome(() => repo.restore('bad')),
        };

        for (final entry in results.entries) {
          expect(
            entry.value,
            isNot(isA<FormatException>()),
            reason: '${entry.key} leaked a FormatException',
          );
        }
        expect(results['findById'], isA<DataCorruptedException>());
        expect(results['watchRecent'], isA<DataCorruptedException>());
      });
    });
  });
}
