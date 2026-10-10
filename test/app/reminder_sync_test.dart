import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/open_and_seed_database.dart';
import 'package:money_app/app/reminder_sync.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/categories/data/categories_repository_impl.dart';
import 'package:money_app/features/recurring/data/recurring_repository_impl.dart';
import 'package:money_app/features/recurring/data/reminders_channel.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/domain/reminder_plan.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../support/fake_id_generator.dart';
import '../support/fixed_clock.dart';
import '../support/in_memory_database.dart';
import '../support/settle_database.dart';

/// Цепочка чтений из базы идёт в нескольких «настоящих» окнах времени.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await settleDatabase(tester);
  }
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  testWidgets('синхронизатор: создание, удаление, смена времени', (
    tester,
  ) async {
    final clock = FixedClock(DateTime(2026, 10, 10, 12));
    final settings = AppSettingsController();
    addTearDown(settings.dispose);
    // Каждый вызов канала: (метод, список элементов).
    final calls = <(String, List<Map<Object?, Object?>>)>[];
    final channel = RemindersChannel(
      invoke: (method, [arguments]) async {
        calls.add((
          method,
          [for (final m in (arguments as List?) ?? []) m as Map],
        ));
        return null;
      },
    );
    late AppDatabase db;
    late DriftRecurringRepository recurring;
    late String categoryId;
    await tester.runAsync(() async {
      db = await openAndSeedDatabase(
        openInMemoryDatabase,
        idGenerator: FakeIdGenerator(prefix: 'seed'),
        clock: clock,
      );
      addTearDown(db.close);
      final all = await DriftCategoriesRepository(
        db,
        clock: clock,
      ).watchAll().first;
      categoryId = all.firstWhere((c) => c.name == 'Связь').id;
      recurring = DriftRecurringRepository(
        db,
        DriftTransactionsRepository(db, clock: clock),
        clock: clock,
      );
    });

    await tester.pumpWidget(
      AppScopeHost(
        database: db,
        settings: settings,
        clock: clock,
        idGenerator: FakeIdGenerator(prefix: 'tx'),
        child: ReminderSyncHost(channel: channel, child: const SizedBox()),
      ),
    );
    await settle(tester);
    // Платежей нет: план пустой и совпадает с «ничего не передавали»? Нет:
    // первый пересчёт всё равно ставит пустой план один раз.
    expect(calls.length, 1);
    expect(calls.single.$2, isEmpty);

    await tester.runAsync(
      () => recurring.create(
        RecurringPayment(
          id: 'pay-1',
          title: 'Интернет',
          type: TransactionType.expense,
          amount: Money.fromMinor(65000, 'RUB'),
          categoryId: categoryId,
          unit: RepeatUnit.month,
          every: 1,
          startsOn: DateOnly(2026, 10, 20),
        ),
      ),
    );
    await settle(tester);
    expect(calls.length, 2);
    expect(calls.last.$1, 'replaceAll');
    final first = calls.last.$2.first;
    expect(first['day'], 20);
    expect(first['hour'], 10);
    expect(first['title'], 'Платёж сегодня: Интернет');
    expect(first['body'], contains('Связь'));

    // Смена времени перепланирует.
    settings.setReminderTime(ReminderTime(9, 30));
    await settle(tester);
    expect(calls.length, 3);
    expect(calls.last.$2.first['hour'], 9);
    expect(calls.last.$2.first['minute'], 30);

    // Смена темы план не меняет: канал не вызывается.
    settings.setThemeMode(ThemeMode.dark);
    await settle(tester);
    expect(calls.length, 3);

    // Удаление платежа перепланирует.
    await tester.runAsync(() => recurring.softDelete('pay-1'));
    await settle(tester);
    expect(calls.length, 4);
    expect(calls.last.$2, isEmpty);

    // Выгрузка виджета до закрытия базы.
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });

  testWidgets('ошибка канала не роняет приложение и повторяется позже', (
    tester,
  ) async {
    final clock = FixedClock(DateTime(2026, 10, 10, 12));
    final settings = AppSettingsController();
    addTearDown(settings.dispose);
    var attempts = 0;
    final channel = RemindersChannel(
      invoke: (method, [arguments]) async {
        attempts++;
        throw StateError('нет канала');
      },
    );
    late AppDatabase db;
    await tester.runAsync(() async {
      db = await openAndSeedDatabase(
        openInMemoryDatabase,
        idGenerator: FakeIdGenerator(prefix: 'seed'),
        clock: clock,
      );
      addTearDown(db.close);
    });
    await tester.pumpWidget(
      AppScopeHost(
        database: db,
        settings: settings,
        clock: clock,
        child: ReminderSyncHost(channel: channel, child: const SizedBox()),
      ),
    );
    await settle(tester);
    expect(attempts, greaterThan(0));
    final before = attempts;
    settings.setReminderTime(ReminderTime(8, 0));
    await settle(tester);
    // План не принят системой, поэтому пробуем снова.
    expect(attempts, greaterThan(before));
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
