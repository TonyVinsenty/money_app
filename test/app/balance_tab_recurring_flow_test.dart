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
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/data/accounts_repository_impl.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/recurring/presentation/due_section.dart';
import 'package:money_app/features/recurring/presentation/recurring_form_screen.dart';
import 'package:money_app/features/recurring/presentation/recurring_section.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';

import '../support/fake_id_generator.dart';
import '../support/fixed_clock.dart';
import '../support/in_memory_database.dart';
import '../support/settle_database.dart';

/// Сборка вкладки «Баланс» на настоящей базе в памяти: платёж на сегодня
/// сразу виден в «К оплате», «Оплачено» убирает его (шаг 6.13b).
void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  testWidgets('платёж на сегодня: «Сохранить» -> «К оплате» -> «Оплачено»', (
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
      await DriftAccountsRepository(db, clock: clock).create(
        Account(
          id: 'acc-card',
          name: 'Карта',
          iconKey: 'card',
          openingBalance: Money.zero('RUB'),
          sortOrder: 0,
          currencyDigits: 2,
        ),
      );
    });
    await settings.setDefaultAccountId('acc-card');

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
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Баланс'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(DueSection.titleKey), findsNothing);

    // Форма: основной счёт и сегодняшний день уже выбраны.
    await tester.tap(find.byKey(RecurringSection.addButtonKey));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(RecurringFormScreen.accountKey),
        matching: find.text('Карта'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(RecurringFormScreen.firstKey),
        matching: find.text('Сегодня'),
      ),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(RecurringFormScreen.nameFieldKey),
      'Интернет',
    );
    await tester.enterText(find.byType(EditableText).last, '650');
    await tester.tap(find.byKey(RecurringFormScreen.categoryKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Связь'));
    await settleDatabase(tester);
    expect(find.byType(RecurringFormScreen), findsOneWidget);
    await tester.tap(find.byKey(RecurringFormScreen.saveKey));
    await settleDatabase(tester);
    expect(find.byType(RecurringFormScreen), findsNothing);

    // Без перезапуска и смены дня запись уже в «К оплате».
    expect(find.text('К оплате (1)'), findsOneWidget);
    expect(
      find.text('Интернет · ${formatMoney(Money.fromMinor(65000, 'RUB'))}'),
      findsOneWidget,
    );

    final payButton = find.byWidgetPredicate((w) {
      final key = w.key;
      return key is ValueKey<String> && key.value.startsWith('due-pay-');
    });
    await tester.tap(payButton);
    await settleDatabase(tester);
    expect(find.byKey(DueSection.titleKey), findsNothing);
    expect(find.textContaining('Сохранено: расход'), findsOneWidget);
    final saved = await tester.runAsync(
      () => DriftTransactionsRepository(db, clock: clock).findAllLive(),
    );
    expect(saved, hasLength(1));
    expect(saved!.single.note, 'Интернет');
    expect(saved.single.accountId, 'acc-card');
  });
}
