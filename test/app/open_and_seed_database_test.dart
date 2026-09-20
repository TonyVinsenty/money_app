import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/open_and_seed_database.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/features/categories/data/categories_repository_impl.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';

import '../support/fake_id_generator.dart';
import '../support/fixed_clock.dart';

/// База, которая запоминает, что её закрыли, и может при закрытии бросить
/// свою ошибку (после настоящего закрытия, чтобы не оставить соединение).
class _SpyDatabase extends AppDatabase {
  _SpyDatabase({this.closeError}) : super(NativeDatabase.memory());

  final StateError? closeError;
  int closeCalls = 0;

  @override
  Future<void> close() async {
    closeCalls++;
    await super.close();
    final error = closeError;
    if (error != null) {
      throw error;
    }
  }
}

/// Генератор, который на втором вызове бросает заранее заготовленную ошибку.
final class _FailingIdGenerator implements IdGenerator {
  _FailingIdGenerator(this.error);

  final StateError error;
  int _calls = 0;

  @override
  String newId() {
    _calls++;
    if (_calls == 2) {
      throw error;
    }
    return 'id-$_calls';
  }
}

void main() {
  group('openAndSeedDatabase', () {
    test('засевает 14 категорий: 10 расходных и 4 доходных', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final opened = await openAndSeedDatabase(
        () async => db,
        idGenerator: FakeIdGenerator(),
        clock: FixedClock(DateTime.utc(2026, 9, 20, 12)),
      );

      expect(opened, same(db));
      expect(await db.select(db.categories).get(), hasLength(14));
      final repository = DriftCategoriesRepository(db);
      expect(
        await repository.watchTopLevel(CategoryKind.expense).first,
        hasLength(10),
      );
      expect(
        await repository.watchTopLevel(CategoryKind.income).first,
        hasLength(4),
      );
    });

    test('работает и с настоящими часами и генератором по умолчанию', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await openAndSeedDatabase(() async => db);

      expect(await db.select(db.categories).get(), hasLength(14));
    });

    test('повторный вызов на той же базе ничего не дублирует', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await openAndSeedDatabase(() async => db);
      final before = await db.select(db.categories).get();
      await openAndSeedDatabase(() async => db);

      final after = await db.select(db.categories).get();
      expect(after, hasLength(14));
      expect(after, unorderedEquals(before));
    });

    test('ошибка открытия пробрасывается как есть', () async {
      final boom = StateError('open-failed');

      await expectLater(
        openAndSeedDatabase(() => Future<AppDatabase>.error(boom)),
        throwsA(same(boom)),
      );
    });

    test('при падении засева база закрывается, ошибка исходная', () async {
      final db = _SpyDatabase();
      final boom = StateError('seed-failed');

      await expectLater(
        openAndSeedDatabase(
          () async => db,
          idGenerator: _FailingIdGenerator(boom),
        ),
        throwsA(same(boom)),
      );

      expect(db.closeCalls, 1);
    });

    test('ошибка закрытия не затирает исходную ошибку засева', () async {
      final db = _SpyDatabase(closeError: StateError('close-failed'));
      final boom = StateError('seed-failed');

      await expectLater(
        openAndSeedDatabase(
          () async => db,
          idGenerator: _FailingIdGenerator(boom),
        ),
        throwsA(same(boom)),
      );

      expect(db.closeCalls, 1);
    });

    test('при успехе база остаётся открытой', () async {
      final db = _SpyDatabase();
      addTearDown(db.close);

      await openAndSeedDatabase(() async => db, idGenerator: FakeIdGenerator());

      expect(db.closeCalls, 0);
    });
  });
}
