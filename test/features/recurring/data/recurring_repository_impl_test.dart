import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/errors/data_corrupted_exception.dart';
import 'package:money_app/features/accounts/data/accounts_repository_impl.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/categories/data/categories_repository_impl.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/recurring/data/recurring_repository_impl.dart';
import 'package:money_app/features/recurring/domain/recurring_repository.dart';

import '../../../support/fixed_clock.dart';
import '../recurring_repository_contract.dart';

final class _DriftHarness implements RecurringHarness {
  _DriftHarness() {
    db = AppDatabase(NativeDatabase.memory());
    repository = DriftRecurringRepository(db, clock: clock);
    _categories = DriftCategoriesRepository(db, clock: clock);
    _accounts = DriftAccountsRepository(db, clock: clock);
  }

  late final AppDatabase db;
  late final DriftRecurringRepository repository;
  late final DriftCategoriesRepository _categories;
  late final DriftAccountsRepository _accounts;

  @override
  final clock = FixedClock(DateTime.utc(2026, 10, 10, 12));

  @override
  RecurringRepository get repo => repository;

  @override
  Future<void> addCategory(Category category) => _categories.create(category);

  @override
  Future<void> addAccount(Account account) => _accounts.create(account);

  @override
  Future<void> archiveCategory(String id) => _categories.archive(id);

  @override
  Future<void> archiveAccount(String id) => _accounts.archive(id);

  @override
  Future<void> close() => db.close();
}

void main() {
  runRecurringRepositoryContract('drift', () async => _DriftHarness());

  group('DriftRecurringRepository (storage details)', () {
    late _DriftHarness h;

    setUp(() async {
      h = _DriftHarness();
      await h.addCategory(
        Category.topLevel(
          id: 'food',
          kind: CategoryKind.expense,
          name: 'Food',
          iconKey: 'tag',
          sortOrder: 0,
        ),
      );
    });

    tearDown(() => h.close());

    test('a currency outside the catalog is corrupted data', () async {
      await h.repo.create(payment('a'));
      await h.db.customStatement(
        "UPDATE recurring_payments SET currency = 'XXX' WHERE id = 'a'",
      );
      await expectLater(
        h.repo.findById('a'),
        throwsA(isA<DataCorruptedException>()),
      );
      await expectLater(
        h.repo.watchAll().first,
        throwsA(isA<DataCorruptedException>()),
      );
    });

    test('soft delete keeps the row and sets deleted_at', () async {
      await h.repo.create(payment('a'));
      await h.repo.softDelete('a');
      final row = await h.db.select(h.db.recurringPayments).getSingle();
      expect(row.deletedAt, h.clock.now().millisecondsSinceEpoch);
    });
  });
}
