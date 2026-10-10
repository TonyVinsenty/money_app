import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart' show AppScopeHost;
import 'package:money_app/app/app_shell.dart';
import 'package:money_app/app/app_tabs.dart';
import 'package:money_app/app/browse_scope.dart';
import 'package:money_app/app/open_and_seed_database.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/categories/data/categories_repository_impl.dart';
import 'package:money_app/features/recurring/data/recurring_repository_impl.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/presentation/due_banner.dart';
import 'package:money_app/features/recurring/presentation/due_section.dart';
import 'package:money_app/features/recurring/presentation/due_tab_badge.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../support/fake_id_generator.dart';
import '../support/fixed_clock.dart';
import '../support/in_memory_database.dart';
import '../support/settle_database.dart';

/// Плашка «К оплате» на «Главной» на настоящей базе в памяти (шаг 6.14):
/// платёж на завтра -> наступил день -> плашка -> «Оплачено» -> «История» и
/// итоги месяца.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  testWidgets('наступил день: плашка -> «Оплачено» -> «История» и итоги', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final clock = FixedClock(DateTime(2026, 10, 10, 12));
    final settings = AppSettingsController();
    addTearDown(settings.dispose);
    late AppDatabase db;
    await tester.runAsync(() async {
      db = await openAndSeedDatabase(
        openInMemoryDatabase,
        idGenerator: FakeIdGenerator(prefix: 'seed'),
        clock: clock,
      );
      addTearDown(db.close);
      final categories = await DriftCategoriesRepository(
        db,
        clock: clock,
      ).watchAll().first;
      final communication = categories.firstWhere((c) => c.name == 'Связь');
      final recurring = DriftRecurringRepository(
        db,
        DriftTransactionsRepository(db, clock: clock),
        clock: clock,
      );
      await recurring.create(
        RecurringPayment(
          id: 'pay-1',
          title: 'Интернет',
          type: TransactionType.expense,
          amount: Money.fromMinor(65000, 'RUB'),
          categoryId: communication.id,
          unit: RepeatUnit.month,
          every: 1,
          startsOn: DateOnly(2026, 10, 11),
        ),
      );
    });

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: MoneyApp.appLocale,
        supportedLocales: MoneyApp.supportedLocales,
        localizationsDelegates: MoneyApp.localizationsDelegates,
        onGenerateRoute: onGenerateAppRoute,
        home: AppScopeHost(
          database: db,
          settings: settings,
          clock: clock,
          idGenerator: FakeIdGenerator(prefix: 'tx'),
          child: BrowseHost(
            child: Builder(
              builder: (context) => AppShell(
                tabs: defaultAppTabs,
                selectedTab: BrowseScope.selectedTabOf(context),
              ),
            ),
          ),
        ),
      ),
    );
    await settleDatabase(tester);
    // Платёж ещё не наступил: плашки нет.
    expect(find.byKey(DueBanner.bannerKey), findsNothing);

    // Наступил следующий день, приложение вернулось из фона.
    clock.advance(const Duration(days: 1));
    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
    await settleDatabase(tester);
    final money = formatMoney(Money.fromMinor(65000, 'RUB'));
    final dash = String.fromCharCode(0x2014);
    expect(find.text('К оплате: Интернет $dash $money'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(DueTabBadge.badgeKey),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );

    // Тап по плашке открывает «Баланс» с блоком «К оплате».
    await tester.tap(find.byKey(DueBanner.bannerKey));
    await settleDatabase(tester);
    expect(find.byKey(DueSection.titleKey), findsOneWidget);

    final payButton = find.byWidgetPredicate((w) {
      final key = w.key;
      return key is ValueKey<String> && key.value.startsWith('due-pay-');
    });
    await tester.tap(payButton);
    await settleDatabase(tester);
    expect(find.byKey(DueSection.titleKey), findsNothing);
    expect(find.byKey(DueTabBadge.badgeKey), findsNothing);

    // В «Истории» появилась операция.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('История'),
      ),
    );
    await settleDatabase(tester);
    expect(find.textContaining('Интернет'), findsWidgets);

    // На «Главной» плашки нет, а расход вошёл в итоги месяца.
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Главная'),
      ),
    );
    await settleDatabase(tester);
    expect(find.byKey(DueBanner.bannerKey), findsNothing);
    final minus = String.fromCharCode(0x2212);
    expect(find.text('$minus$money'), findsWidgets);
  });
}
