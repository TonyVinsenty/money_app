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
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/presentation/account_screen.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../support/fake_id_generator.dart';
import '../support/fixed_clock.dart';
import '../support/in_memory_database.dart';

/// «История» по счёту (шаг 5.15): «Баланс» -> счёт -> «Операции».
late AppDatabase _db;
late AppSettingsController _settings;

Account _account(String id, String name, String currency, int order) => Account(
  id: id,
  name: name,
  iconKey: 'card',
  openingBalance: Money.zero(currency),
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
    final category =
        await (_db.select(_db.categories)
              ..where((c) => c.kind.equals('expense') & c.parentId.isNull())
              ..limit(1))
            .getSingle();
    final accounts = DriftAccountsRepository(_db, clock: clock);
    await accounts.create(_account('acc-card', 'Карта', 'RUB', 0));
    await accounts.create(_account('acc-cash', 'Наличные', 'RUB', 1));
    await accounts.create(_account('acc-usd', 'Доллары', 'USD', 2));
    final transactions = DriftTransactionsRepository(_db, clock: clock);
    Future<void> add(String id, String note, String? accountId) =>
        transactions.add(
          Transaction(
            id: id,
            type: TransactionType.expense,
            amount: Money.fromMinor(10000, 'RUB'),
            occurredOn: DateOnly(2026, 9, 10),
            occurredAt: DateTime.utc(2026, 9, 10, 9),
            categoryId: category.id,
            note: note,
            accountId: accountId,
          ),
        );
    await add('t1', 'note-card', 'acc-card');
    await add('t2', 'note-cash', 'acc-cash');
    await add('t3', 'note-none', null);
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
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Future<void> _openAccount(WidgetTester tester, String name) async {
  await _openTab(tester, 'Баланс');
  await tester.ensureVisible(find.text(name));
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  testWidgets('«Операции» открывает «Историю» с полоской и фильтром по '
      'счёту; «Сбросить» и поиск поверх фильтра', (tester) async {
    await _pumpApp(tester);
    await _openAccount(tester, 'Карта');
    await tester.tap(find.byKey(AccountScreen.operationsKey));
    await tester.pumpAndSettle();

    expect(find.byType(AccountScreen), findsNothing);
    expect(find.text('Фильтр: Счёт: Карта'), findsOneWidget);
    expect(find.text('note-card'), findsOneWidget);
    expect(find.text('note-cash'), findsNothing);
    expect(find.text('note-none'), findsNothing);

    // Поиск работает поверх фильтра по счёту.
    BrowseScope.of(tester.element(find.byType(AppShell)))
        .setHistorySearch('note-c');
    await tester.pumpAndSettle();
    expect(find.text('note-card'), findsOneWidget);
    expect(find.text('note-cash'), findsNothing);
    BrowseScope.of(tester.element(find.byType(AppShell))).setHistorySearch('');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Сбросить').first);
    await tester.pumpAndSettle();
    expect(find.text('Фильтр: Счёт: Карта'), findsNothing);
    expect(find.text('note-cash'), findsOneWidget);
    expect(find.text('note-none'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('уход из «Истории» снимает фильтр по счёту', (tester) async {
    await _pumpApp(tester);
    await _openAccount(tester, 'Наличные');
    await tester.tap(find.byKey(AccountScreen.operationsKey));
    await tester.pumpAndSettle();
    expect(find.text('Фильтр: Счёт: Наличные'), findsOneWidget);
    await _openTab(tester, 'Главная');
    await _openTab(tester, 'История');
    expect(find.text('Фильтр: Счёт: Наличные'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('у счёта в другой валюте кнопки «Операции» нет', (tester) async {
    await _pumpApp(tester);
    await _openAccount(tester, 'Доллары');
    expect(find.byType(AccountScreen), findsOneWidget);
    expect(find.byKey(AccountScreen.operationsKey), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
