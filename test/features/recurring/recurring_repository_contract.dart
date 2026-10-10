import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/domain/recurring_repository.dart';
import 'package:money_app/features/recurring/domain/recurring_rules.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../support/fixed_clock.dart';

/// Что нужно общему набору тестов от конкретной реализации (настоящей или
/// фейка): сам репозиторий, часы и способ положить в «базу» категории и счета.
abstract class RecurringHarness {
  RecurringRepository get repo;
  FixedClock get clock;
  Future<void> addCategory(Category category);
  Future<void> addAccount(Account account);
  Future<void> archiveCategory(String id);
  Future<void> archiveAccount(String id);
  Future<void> close();
}

Account _account(String id, String currency) => Account(
  id: id,
  name: 'Account $id',
  iconKey: 'card',
  openingBalance: Money.fromMinor(0, currency),
  sortOrder: 0,
  currencyDigits: 2,
);

Category _top(String id, CategoryKind kind) => Category.topLevel(
  id: id,
  kind: kind,
  name: 'Name $id',
  iconKey: 'tag',
  sortOrder: 0,
);

Category _sub(String id, Category parent) => Category.subcategoryOf(
  id: id,
  parent: parent,
  name: 'Name $id',
  iconKey: 'tag',
  sortOrder: 0,
);

RecurringPayment payment(
  String id, {
  String title = 'Internet',
  TransactionType type = TransactionType.expense,
  String currency = 'RUB',
  String categoryId = 'food',
  String? subcategoryId,
  String? accountId,
  DateOnly? startsOn,
  DateOnly? endsOn,
  RepeatUnit unit = RepeatUnit.month,
  int every = 1,
  DateOnly? trackedThrough,
}) {
  return RecurringPayment(
    id: id,
    title: title,
    type: type,
    amount: Money.fromMinor(65000, currency),
    categoryId: categoryId,
    subcategoryId: subcategoryId,
    accountId: accountId,
    unit: unit,
    every: every,
    startsOn: startsOn ?? DateOnly(2026, 10, 15),
    endsOn: endsOn,
    trackedThrough: trackedThrough,
  );
}

Matcher _rule(RecurringRule r) =>
    throwsA(isA<RecurringRuleException>().having((e) => e.rule, 'rule', r));

/// Общий набор тестов: одни и те же проверки гоняются на настоящем
/// репозитории (drift, база в памяти) и на фейке, чтобы фейк не расходился с
/// настоящим. «Сегодня» в часах - 2026-10-10.
void runRecurringRepositoryContract(
  String name,
  Future<RecurringHarness> Function() open,
) {
  group('RecurringRepository contract: $name', () {
    late RecurringHarness h;
    late RecurringRepository repo;
    final food = _top('food', CategoryKind.expense);
    final salary = _top('salary', CategoryKind.income);
    final other = _top('other', CategoryKind.expense);

    setUp(() async {
      h = await open();
      repo = h.repo;
      await h.addCategory(food);
      await h.addCategory(_sub('bread', food));
      await h.addCategory(salary);
      await h.addCategory(other);
      await h.addCategory(_sub('other-sub', other));
      await h.addAccount(_account('rub', 'RUB'));
      await h.addAccount(_account('usd', 'USD'));
    });

    tearDown(() => h.close());

    test(
      'create and read back; trackedThrough is the day before startsOn',
      () async {
        await repo.create(
          payment(
            'a',
            subcategoryId: 'bread',
            accountId: 'rub',
            endsOn: DateOnly(2027, 1, 1),
            // Переданное значение игнорируется.
            trackedThrough: DateOnly(2030, 1, 1),
          ),
        );
        final found = (await repo.findById('a'))!;
        expect(
          found,
          payment(
            'a',
            subcategoryId: 'bread',
            accountId: 'rub',
            endsOn: DateOnly(2027, 1, 1),
            trackedThrough: DateOnly(2026, 10, 14),
          ),
        );
        expect(found.createdAt, h.clock.now().toUtc());
        expect(found.updatedAt, found.createdAt);
        expect(await repo.findById('missing'), isNull);
      },
    );

    test(
      'startsOn on the 1st gives the last day of the previous month',
      () async {
        await repo.create(payment('a', startsOn: DateOnly(2026, 11, 1)));
        expect(
          (await repo.findById('a'))!.trackedThrough,
          DateOnly(2026, 10, 31),
        );
      },
    );

    test(
      'watchAll: by next date, ended last, then by title; deleted hidden',
      () async {
        await repo.create(
          payment('late', title: 'Zeta', startsOn: DateOnly(2026, 10, 20)),
        );
        await repo.create(
          payment('soon-b', title: 'beta', startsOn: DateOnly(2026, 10, 12)),
        );
        await repo.create(
          payment('soon-a', title: 'Alpha', startsOn: DateOnly(2026, 10, 12)),
        );
        await repo.create(
          payment(
            'ended',
            title: 'Old',
            startsOn: DateOnly(2026, 1, 5),
            endsOn: DateOnly(2026, 3, 5),
          ),
        );
        await repo.create(payment('gone', startsOn: DateOnly(2026, 10, 11)));
        await repo.softDelete('gone');

        final items = await repo.watchAll().first;
        expect(
          [for (final i in items) i.payment.id],
          ['soon-a', 'soon-b', 'late', 'ended'],
        );
        expect(items[0].nextDue, DateOnly(2026, 10, 12));
        expect(items[2].nextDue, DateOnly(2026, 10, 20));
        expect(items[3].nextDue, isNull);
      },
    );

    test('next date counts today itself', () async {
      await repo.create(payment('a', startsOn: DateOnly(2026, 10, 10)));
      expect(
        (await repo.watchAll().first).single.nextDue,
        DateOnly(2026, 10, 10),
      );
    });

    test('watchAll sends a new list after every write', () async {
      final seen = <List<String>>[];
      final sub = repo.watchAll().listen(
        (items) => seen.add([for (final i in items) i.payment.id]),
      );
      await pumpEventQueue();
      await repo.create(payment('a'));
      await pumpEventQueue();
      await repo.softDelete('a');
      await pumpEventQueue();
      await repo.restore('a');
      await pumpEventQueue();
      await sub.cancel();
      expect(seen, [
        <String>[],
        ['a'],
        <String>[],
        ['a'],
      ]);
    });

    group('links', () {
      test('a payment without a subcategory and an account is fine', () async {
        await repo.create(payment('a'));
        final found = (await repo.findById('a'))!;
        expect(found.subcategoryId, isNull);
        expect(found.accountId, isNull);
      });

      test('unknown category, subcategory or account: ArgumentError', () async {
        await expectLater(
          repo.create(payment('a', categoryId: 'nope')),
          throwsArgumentError,
        );
        await expectLater(
          repo.create(payment('a', subcategoryId: 'nope')),
          throwsArgumentError,
        );
        await expectLater(
          repo.create(payment('a', accountId: 'nope')),
          throwsArgumentError,
        );
      });

      test('a subcategory as the category', () async {
        await expectLater(
          repo.create(payment('a', categoryId: 'bread')),
          _rule(RecurringRule.categoryMustBeTopLevel),
        );
      });

      test('category of another kind', () async {
        await expectLater(
          repo.create(payment('a', categoryId: 'salary')),
          _rule(RecurringRule.typeKindMismatch),
        );
        await expectLater(
          repo.create(payment('a', type: TransactionType.income)),
          _rule(RecurringRule.typeKindMismatch),
        );
      });

      test('subcategory of another category', () async {
        await expectLater(
          repo.create(payment('a', subcategoryId: 'other-sub')),
          _rule(RecurringRule.subcategoryNotOfCategory),
        );
      });

      test('archived category and archived subcategory', () async {
        await h.archiveCategory('bread');
        await expectLater(
          repo.create(payment('a', subcategoryId: 'bread')),
          _rule(RecurringRule.categoryArchived),
        );
        await h.archiveCategory('food');
        await expectLater(
          repo.create(payment('a')),
          _rule(RecurringRule.categoryArchived),
        );
      });

      test('account of another currency and archived account', () async {
        await expectLater(
          repo.create(payment('a', accountId: 'usd')),
          _rule(RecurringRule.accountCurrencyMismatch),
        );
        await h.archiveAccount('rub');
        await expectLater(
          repo.create(payment('a', accountId: 'rub')),
          _rule(RecurringRule.accountArchived),
        );
      });

      test('a failed create leaves nothing behind', () async {
        await expectLater(
          repo.create(payment('a', categoryId: 'salary')),
          throwsA(isA<RecurringRuleException>()),
        );
        expect(await repo.findById('a'), isNull);
        expect(await repo.watchAll().first, isEmpty);
      });
    });

    group('update', () {
      test('replaces fields, keeps trackedThrough and createdAt', () async {
        await repo.create(payment('a', accountId: 'rub'));
        h.clock.value = h.clock.value.add(const Duration(hours: 1));
        final before = (await repo.findById('a'))!;
        final changed = payment(
          'a',
          title: 'Rent',
          categoryId: 'other',
          subcategoryId: 'other-sub',
          startsOn: DateOnly(2026, 12, 1),
          endsOn: DateOnly(2027, 12, 1),
          unit: RepeatUnit.year,
          every: 2,
          trackedThrough: DateOnly(2030, 1, 1),
        ).withAmount(Money.fromMinor(1, 'RUB')).withRemind(false);
        await repo.update(changed);
        final after = (await repo.findById('a'))!;
        expect(after, changed.withTrackedThrough(before.trackedThrough));
        expect(after.createdAt, before.createdAt);
        expect(after.updatedAt, h.clock.now().toUtc());
      });

      test('unknown or deleted payment is an ArgumentError', () async {
        await expectLater(repo.update(payment('nope')), throwsArgumentError);
        await repo.create(payment('a'));
        await repo.softDelete('a');
        await expectLater(repo.update(payment('a')), throwsArgumentError);
      });

      test('the same links are checked as on create', () async {
        await repo.create(payment('a'));
        await expectLater(
          repo.update(payment('a', categoryId: 'salary')),
          _rule(RecurringRule.typeKindMismatch),
        );
        await expectLater(
          repo.update(payment('a', accountId: 'usd')),
          _rule(RecurringRule.accountCurrencyMismatch),
        );
        expect((await repo.findById('a'))!.categoryId, 'food');
      });

      test('archive is checked only for links that changed', () async {
        await repo.create(
          payment('a', subcategoryId: 'bread', accountId: 'rub'),
        );
        await h.archiveCategory('bread');
        await h.archiveCategory('food');
        await h.archiveAccount('rub');
        // Старые связи остаются, пусть и в архиве: правится только название.
        await repo.update(
          payment('a', title: 'New', subcategoryId: 'bread', accountId: 'rub'),
        );
        expect((await repo.findById('a'))!.title, 'New');
        // Новая связь с архивной категорией или счётом - нельзя.
        await repo.create(payment('b', categoryId: 'other'));
        await expectLater(
          repo.update(payment('b', categoryId: 'food')),
          _rule(RecurringRule.categoryArchived),
        );
        await expectLater(
          repo.update(payment('b', categoryId: 'other', accountId: 'rub')),
          _rule(RecurringRule.accountArchived),
        );
      });
    });

    group('delete and undo', () {
      test('softDelete hides the payment, restore brings it back', () async {
        await repo.create(payment('a'));
        final before = (await repo.findById('a'))!;
        await repo.softDelete('a');
        expect(await repo.findById('a'), isNull);
        expect(await repo.watchAll().first, isEmpty);
        await repo.restore('a');
        expect(await repo.findById('a'), before);
        expect((await repo.watchAll().first).single.payment.id, 'a');
      });

      test(
        'deleting a missing or already deleted payment: ArgumentError',
        () async {
          await expectLater(repo.softDelete('nope'), throwsArgumentError);
          await repo.create(payment('a'));
          await repo.softDelete('a');
          await expectLater(repo.softDelete('a'), throwsArgumentError);
        },
      );

      test(
        'restore: live payment unchanged, missing is ArgumentError',
        () async {
          await repo.create(payment('a'));
          final before = (await repo.findById('a'))!;
          h.clock.value = h.clock.value.add(const Duration(hours: 1));
          await repo.restore('a');
          expect((await repo.findById('a'))!.updatedAt, before.updatedAt);
          await expectLater(repo.restore('nope'), throwsArgumentError);
        },
      );
    });
  });
}
