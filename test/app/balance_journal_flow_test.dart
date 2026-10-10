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
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/data/accounts_repository_impl.dart';
import 'package:money_app/features/accounts/data/transfers_repository_impl.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/transfer.dart';
import 'package:money_app/features/accounts/presentation/account_screen.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';
import 'package:money_app/features/accounts/presentation/accounts_section.dart';
import 'package:money_app/features/accounts/presentation/balance_journal_screen.dart';
import 'package:money_app/features/accounts/presentation/transfer_form_screen.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/domain/history_view.dart';

import '../support/fake_id_generator.dart';
import '../support/fixed_clock.dart';
import '../support/in_memory_database.dart';

/// «История счетов»: «Баланс» -> «История» -> перевод / счёт (шаг j.4).
late AppDatabase _db;
late AppSettingsController _settings;

Account _account(String id, String name, int order) => Account(
  id: id,
  name: name,
  iconKey: 'card',
  openingBalance: Money.zero('RUB'),
  sortOrder: order,
  currencyDigits: 2,
);

Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final clock = FixedClock(DateTime(2026, 9, 30, 15));
  _settings = AppSettingsController();
  addTearDown(_settings.dispose);
  await tester.runAsync(() async {
    _db = await openAndSeedDatabase(
      openInMemoryDatabase,
      idGenerator: FakeIdGenerator(prefix: 'seed'),
      clock: clock,
    );
    addTearDown(_db.close);
    final accounts = DriftAccountsRepository(_db, clock: clock);
    await accounts.create(_account('acc-card', 'Карта', 0));
    await accounts.create(_account('acc-cash', 'Наличные', 1));
    await DriftTransfersRepository(_db, clock: clock).add(
      Transfer(
        id: 'tr1',
        fromAccountId: 'acc-card',
        toAccountId: 'acc-cash',
        amount: Money.fromMinor(500000, 'RUB'),
        occurredOn: DateOnly(2026, 9, 30),
        occurredAt: clock.now().toUtc().add(const Duration(hours: 1)),
      ),
    );
    await accounts.archive('acc-cash');
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: MoneyApp.appLocale,
      supportedLocales: MoneyApp.supportedLocales,
      localizationsDelegates: MoneyApp.localizationsDelegates,
      onGenerateRoute: onGenerateAppRoute,
      home: AppScopeHost(
        database: _db,
        settings: _settings,
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
  await tester.tap(find.byKey(AccountsSection.journalKey));
  await tester.pumpAndSettle();
}

List<String> _titles(WidgetTester tester) => [
  for (final t in tester.widgetList<ListTile>(
    find.descendant(
      of: find.byType(BalanceJournalScreen),
      matching: find.byType(ListTile),
    ),
  ))
    (t.title! as Text).data!,
];

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  const transferTitle = 'Карта → Наличные (в архиве)';

  testWidgets('journal shows four rows in order; transfer opens the form, '
      'delete and undo work', (tester) async {
    await _pumpApp(tester);
    expect(find.text(balanceJournalTitle), findsOneWidget);
    expect(_titles(tester), [
      transferTitle,
      journalArchivedTitle('Наличные'),
      journalCreatedTitle('Карта'),
      journalCreatedTitle('Наличные'),
    ]);

    await tester.tap(find.text(transferTitle));
    await tester.pumpAndSettle();
    expect(find.byType(TransferFormScreen), findsOneWidget);
    expect(find.text(transferFormEditTitle), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.byType(BalanceJournalScreen), findsOneWidget);
    expect(find.text(transferTitle), findsNothing);
    expect(_titles(tester), hasLength(3));

    await tester.tap(find.text(transferUndoLabel));
    await tester.pumpAndSettle();
    expect(_titles(tester), hasLength(4));
    expect(find.text(transferTitle), findsOneWidget);
  });

  testWidgets('tap on an account row opens the account screen', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text(journalCreatedTitle('Карта')));
    await tester.pumpAndSettle();
    expect(find.byType(AccountScreen), findsOneWidget);
  });

  testWidgets('rows of an archived account do nothing on tap', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text(journalArchivedTitle('Наличные')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(journalCreatedTitle('Наличные')));
    await tester.pumpAndSettle();
    expect(find.byType(AccountScreen), findsNothing);
    expect(find.byType(BalanceJournalScreen), findsOneWidget);
  });

  testWidgets('"Операции" from the journal closes both screens and opens '
      'History filtered by the account', (tester) async {
    await _pumpApp(tester);
    await tester.tap(find.text(journalCreatedTitle('Карта')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(AccountScreen.operationsKey));
    await tester.tap(find.byKey(AccountScreen.operationsKey));
    await tester.pumpAndSettle();
    expect(find.byType(AccountScreen), findsNothing);
    expect(find.byType(BalanceJournalScreen), findsNothing);
    expect(
      BrowseScope.selectedTabOf(tester.element(find.byType(AppShell))).value,
      historyTabIndex,
    );
    expect(
      BrowseScope.of(tester.element(find.byType(AppShell))).historyFilter,
      HistoryFilter.account('acc-card'),
    );
  });
}
