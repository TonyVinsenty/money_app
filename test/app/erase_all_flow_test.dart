import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart' show AppScopeHost;
import 'package:money_app/app/app_shell.dart';
import 'package:money_app/app/app_tabs.dart';
import 'package:money_app/app/balance_tab.dart' show adoptFirstAccountAsDefault;
import 'package:money_app/app/browse_controller.dart';
import 'package:money_app/app/browse_scope.dart';
import 'package:money_app/app/open_and_seed_database.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/period_switcher.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/data/accounts_repository_impl.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/presentation/accounts_section.dart';
import 'package:money_app/features/categories/domain/default_categories.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/history_view.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/quick_add/account_chip.dart';

import '../support/fake_id_generator.dart';
import '../support/fixed_clock.dart';
import '../support/in_memory_database.dart';

/// «Очистить всё» целиком (шаг 5.O3): настоящая база в памяти, все вкладки.
late AppDatabase _db;
late AppSettingsController _settings;
late FixedClock _clock;

Account _account(String id, String name, String currency, int order) => Account(
  id: id,
  name: name,
  iconKey: 'card',
  openingBalance: Money.zero(currency),
  sortOrder: order,
  currencyDigits: 2,
);

Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _clock = FixedClock(DateTime(2026, 10, 10, 15));
  _settings = AppSettingsController();
  addTearDown(_settings.dispose);
  await tester.runAsync(() async {
    _db = await openAndSeedDatabase(
      openInMemoryDatabase,
      idGenerator: FakeIdGenerator(prefix: 'seed'),
      clock: _clock,
    );
    addTearDown(_db.close);
    final category =
        await (_db.select(_db.categories)
              ..where((c) => c.kind.equals('expense') & c.parentId.isNull())
              ..limit(1))
            .getSingle();
    final accounts = DriftAccountsRepository(_db, clock: _clock);
    await accounts.create(_account('acc-card', 'Карта', 'RUB', 0));
    final transactions = DriftTransactionsRepository(_db, clock: _clock);
    Future<void> add(String id, String note, DateOnly day) => transactions.add(
      Transaction(
        id: id,
        type: TransactionType.expense,
        amount: Money.fromMinor(12300, 'RUB'),
        occurredOn: day,
        occurredAt: DateTime.utc(day.year, day.month, day.day, 9),
        categoryId: category.id,
        note: note,
        accountId: 'acc-card',
      ),
    );
    await add('t-sep', 'note-sept', DateOnly(2026, 9, 10));
    await add('t-oct', 'note-oct', DateOnly(2026, 10, 5));
  });
  _settings.setThemeMode(ThemeMode.dark);
  _settings.setLastExportDay(DateOnly(2026, 10, 5));
  await _settings.setDefaultAccountId('acc-card');
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
        clock: _clock,
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

BrowseController _browse(WidgetTester tester) =>
    BrowseScope.of(tester.element(find.byType(AppShell)));

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
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

  testWidgets('после «Очистить всё» приложение как при первом запуске', (
    tester,
  ) async {
    await _pumpApp(tester);

    // Данные есть: «История» в прошлом месяце, фильтр, поиск, сортировка.
    final browse = _browse(tester);
    browse.showMonthOf(DateOnly(2026, 9, 1));
    browse.setHistoryFilter(HistoryFilter.account('acc-card'));
    browse.setHistorySort(HistorySort.oldestFirst);
    await tester.pumpAndSettle();
    await _openTab(tester, 'История');
    expect(find.text('note-sept'), findsOneWidget);
    expect(find.text('Фильтр: Счёт: Карта'), findsOneWidget);

    // «Аналитика» в прошлом периоде.
    await _openTab(tester, 'Аналитика');
    await tester.tap(find.byTooltip('Предыдущий месяц'));
    await tester.pumpAndSettle();
    final analyticsLabelBefore = tester
        .widget<PeriodSwitcher>(find.byType(PeriodSwitcher))
        .label;
    await tester.pumpAndSettle();

    // Стираем.
    await _openTab(tester, 'Настройки');
    await tester.tap(find.text('Очистить всё'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Стереть всё'));
    await _settle(tester);

    // База: пусто, категории стандартные.
    final counts = await tester.runAsync(() async {
      Future<int> n(String t) async =>
          (await _db.customSelect('SELECT COUNT(*) AS c FROM $t').getSingle())
              .read<int>('c');
      return [
        await n('transactions'),
        await n('accounts'),
        await n('categories'),
      ];
    });
    expect(counts, [0, 0, defaultCategories.length]);

    // Месяц, фильтры, поиск, сортировка — по умолчанию.
    expect(browse.month, monthRange(DateOnly(2026, 10, 10)));
    expect(browse.historyFilter, HistoryFilter.off);
    expect(browse.historySort, HistorySort.newestFirst);
    expect(browse.historySearch, '');

    // Настройки прежние, ключ основного счёта остался.
    expect(_settings.themeMode, ThemeMode.dark);
    expect(_settings.mainCurrencyCode, 'RUB');
    expect(_settings.lastExportDay, DateOnly(2026, 10, 5));
    expect(_settings.defaultAccountId, 'acc-card');
    expect(find.text('Последний экспорт: 5 октября'), findsOneWidget);

    // «История»: пусто, без полоски фильтра.
    await _openTab(tester, 'История');
    expect(find.text('note-sept'), findsNothing);
    expect(find.text('note-oct'), findsNothing);
    expect(find.textContaining('Фильтр:'), findsNothing);
    expect(find.text('Операций пока нет'), findsOneWidget);

    // «Аналитика»: текущий месяц (переход вперёд невозможен).
    await _openTab(tester, 'Аналитика');
    final switcher = tester.widget<PeriodSwitcher>(find.byType(PeriodSwitcher));
    expect(switcher.label, isNot(analyticsLabelBefore));
    expect(switcher.label.toLowerCase(), contains('октябр'));
    expect(find.byKey(PeriodSwitcher.nextKey), findsNothing);

    // «Баланс»: счетов нет.
    await _openTab(tester, 'Баланс');
    expect(find.text('Карта'), findsNothing);
    expect(find.byKey(AccountsSection.addButtonKey), findsOneWidget);

    await _openTab(tester, 'Главная');
    expect(find.textContaining('123'), findsNothing);
    expect(find.textContaining('Продукт'), findsNothing);

    // Быстрый ввод: стандартные категории, плашки счёта нет.
    await _openTab(tester, 'Главная');
    await tester.tap(find.text('Расход'));
    await _settle(tester);
    expect(find.byKey(AccountChip.chipKey), findsNothing);
    await tester.enterText(find.byType(TextField), '5');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Далее'));
    await _settle(tester);
    final firstExpense = defaultCategories.firstWhere(
      (c) => c.kind.name == 'expense',
    );
    expect(find.text(firstExpense.name), findsOneWidget);
    expect(find.byKey(AccountChip.chipKey), findsNothing);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    // Новый рублёвый счёт становится основным сам.
    final repo = DriftAccountsRepository(_db, clock: _clock);
    final account = _account('acc-new', 'Новый', 'RUB', 0);
    await tester.runAsync(() => repo.create(account));
    // Поток счетов уже слушает вкладка: его ответы идут через часы теста.
    final adopted = adoptFirstAccountAsDefault(account, repo, _settings);
    await _settle(tester);
    await adopted;
    expect(_settings.defaultAccountId, 'acc-new');

    await tester.pumpWidget(const SizedBox());
  });
}
