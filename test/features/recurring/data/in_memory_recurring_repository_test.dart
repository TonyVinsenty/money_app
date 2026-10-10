import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/recurring/domain/recurring_repository.dart';

import '../../../support/fixed_clock.dart';
import '../../../support/in_memory_recurring_repository.dart';
import '../recurring_repository_contract.dart';

final class _FakeHarness implements RecurringHarness {
  @override
  final clock = FixedClock(DateTime.utc(2026, 10, 10, 12));
  late final InMemoryRecurringRepository fake = InMemoryRecurringRepository(
    clock,
  );

  @override
  RecurringRepository get repo => fake;

  @override
  Future<void> addCategory(Category category) async =>
      fake.categories.add(category);

  @override
  Future<void> addAccount(Account account) async => fake.accounts.add(account);

  @override
  Future<void> archiveCategory(String id) async {
    final i = fake.categories.indexWhere((c) => c.id == id);
    fake.categories[i] = fake.categories[i].archived(clock.now().toUtc());
  }

  @override
  Future<void> archiveAccount(String id) async {
    final i = fake.accounts.indexWhere((a) => a.id == id);
    fake.accounts[i] = fake.accounts[i].archived(clock.now().toUtc());
  }

  @override
  Future<void> close() async {}
}

void main() {
  runRecurringRepositoryContract('in-memory fake', () async => _FakeHarness());
}
