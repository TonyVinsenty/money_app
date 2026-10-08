import 'dart:io';

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
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/data/accounts_repository_impl.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/presentation/account_form_screen.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';
import 'package:money_app/features/accounts/presentation/accounts_section.dart';
import 'package:money_app/features/analytics/presentation/category_breakdown_card.dart';
import 'package:money_app/features/analytics/presentation/category_breakdown_screen.dart';
import 'package:money_app/features/categories/data/categories_repository_impl.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/csv_import/data/csv_import_writer.dart';
import 'package:money_app/features/csv_import/domain/parse_csv_import.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/history_view.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../tool/make_test_dataset.dart';
import '../support/fake_id_generator.dart';
import '../support/fixed_clock.dart';
import '../support/in_memory_database.dart';

/// Основная валюта (шаг 5.10o): «История», «Аналитика», экран категории и
/// «Баланс» на настоящей базе в памяти с тестовым набором
/// `zuno-test-dataset.csv` (рубли, июль и сентябрь 2026) и двумя долларовыми
/// операциями в сентябре.
const _septemberExpensesMinor = 12531282; // 125 312,82 (137 операций)
const _julyExpensesMinor = 15295252; // 152 952,52 (146 операций)

late AppDatabase _db;
late AppSettingsController _settings;
late String _groceriesId;

CurrencyInfo get _usd => catalogCurrency('USD')!;
CurrencyInfo get _rub => catalogCurrency('RUB')!;

final _minus = String.fromCharCode(0x2212);

String _money(int minor, String code) =>
    formatMoney(Money.fromMinor(minor, code));

Finder _rich(String text) => find.textContaining(text, findRichText: true);

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpApp(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // Набор разбирается «седьмого октября» (все его даты в прошлом), а само
  // приложение живёт 30 сентября: на «Главной» и в «Истории» - сентябрь.
  final importClock = FixedClock(DateTime.utc(2026, 10, 7, 12));
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
    final categories = DriftCategoriesRepository(_db, clock: clock);
    final transactions = DriftTransactionsRepository(_db, clock: clock);
    final hobby = Category.topLevel(
      id: testDatasetHobbyId,
      kind: CategoryKind.expense,
      name: 'Хобби',
      iconKey: 'palette',
      sortOrder: 10,
    );
    await categories.create(hobby);
    for (final (id, name) in [
      (testDatasetHobbyPaintsId, 'Краски'),
      (testDatasetHobbyBrushesId, 'Кисти'),
    ]) {
      await categories.create(
        Category.subcategoryOf(
          id: id,
          parent: hobby,
          name: name,
          iconKey: 'palette',
          sortOrder: 0,
        ),
      );
    }
    await categories.archive(testDatasetHobbyId);
    final writer = CsvImportWriter(
      db: _db,
      categories: categories,
      transactions: transactions,
      ids: FakeIdGenerator(prefix: 'new'),
    );
    final parsed = parseCsvImport(
      File(testDatasetPath).readAsBytesSync(),
      clock: importClock,
    );
    expect(parsed, isA<CsvImportParsed>());
    await writer.write(await writer.prepare((parsed as CsvImportParsed).rows));

    final groceries =
        await (_db.select(_db.categories)..where(
              (c) => c.name.equals('Продукты') & c.kind.equals('expense'),
            ))
            .getSingle();
    final incomeCategories = await (_db.select(
      _db.categories,
    )..where((c) => c.kind.equals('income') & c.parentId.isNull())).get();
    _groceriesId = groceries.id;
    await transactions.add(
      Transaction(
        id: 'usd-expense',
        type: TransactionType.expense,
        amount: Money.fromMinor(1250, 'USD'),
        occurredOn: DateOnly(2026, 9, 10),
        occurredAt: DateTime.utc(2026, 9, 10, 9),
        categoryId: groceries.id,
        note: 'usd-coffee',
      ),
    );
    await transactions.add(
      Transaction(
        id: 'usd-income',
        type: TransactionType.income,
        amount: Money.fromMinor(10000, 'USD'),
        occurredOn: DateOnly(2026, 9, 11),
        occurredAt: DateTime.utc(2026, 9, 11, 9),
        categoryId: incomeCategories.first.id,
        note: 'usd-bonus',
      ),
    );
    final accounts = DriftAccountsRepository(_db, clock: clock);
    await accounts.create(
      Account(
        id: 'acc-rub',
        name: 'Карта',
        iconKey: 'card',
        openingBalance: Money.fromMinor(100000, 'RUB'),
        sortOrder: 0,
        currencyDigits: 2,
      ),
    );
    await accounts.create(
      Account(
        id: 'acc-usd',
        name: 'Доллары',
        iconKey: 'card',
        openingBalance: Money.fromMinor(5000, 'USD'),
        sortOrder: 1,
        currencyDigits: 2,
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
        database: _db,
        settings: _settings,
        clock: clock,
        idGenerator: FakeIdGenerator(prefix: 'tx'),
        child: BrowseHost(child: AppShell(tabs: defaultAppTabs)),
      ),
    ),
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

  testWidgets('основная USD: «История» - только доллары и итог в долларах; '
      'вернули RUB - набор снова виден, итоги прежние', (tester) async {
    await _pumpApp(tester);
    await _openTab(tester, 'История');
    // Итог показывается у отфильтрованного списка: оставляем одни расходы.
    BrowseScope.of(tester.element(find.byType(AppShell)))
        .setHistoryFilter(HistoryFilter(type: HistoryTypeFilter.expense));
    await tester.pumpAndSettle();
    expect(_rich('137 операций'), findsOneWidget);

    await _settings.setMainCurrency(_usd);
    await tester.pumpAndSettle();
    expect(find.text('usd-coffee'), findsOneWidget);
    expect(find.text('usd-bonus'), findsNothing);
    expect(_rich('1 операция'), findsOneWidget);
    expect(_rich('$_minus${_money(1250, 'USD')}'), findsWidgets);
    expect(_rich('137 операций'), findsNothing);

    await _settings.setMainCurrency(_rub);
    await tester.pumpAndSettle();
    expect(_rich('137 операций'), findsOneWidget);
    expect(find.text('usd-coffee'), findsNothing);

    // Итоги июля и сентября прежние (набор не пострадал от смены валюты).
    final repository = DriftTransactionsRepository(
      _db,
      clock: FixedClock(DateTime.utc(2026, 10, 7)),
    );
    final (september, july) = await tester.runAsync(() async {
      final september = await repository
          .watchTotal(
            type: TransactionType.expense,
            period: monthRange(DateOnly(2026, 9, 1)),
          )
          .first;
      final july = await repository
          .watchTotal(
            type: TransactionType.expense,
            period: monthRange(DateOnly(2026, 7, 1)),
          )
          .first;
      return (september, july);
    }) as (Money, Money);
    expect(september.minorUnits, _septemberExpensesMinor);
    expect(july.minorUnits, _julyExpensesMinor);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('основная USD: «Аналитика» и экран категории в долларах', (
    tester,
  ) async {
    await _pumpApp(tester);
    await _settings.setMainCurrency(_usd);
    await tester.pumpAndSettle();
    await _openTab(tester, 'Аналитика');
    expect(find.textContaining(_money(1250, 'USD')), findsWidgets);
    expect(find.textContaining('₽'), findsNothing);

    await tester.ensureVisible(
      find.byKey(CategoryBreakdownCard.rowKey(_groceriesId)),
    );
    await tester.tap(find.byKey(CategoryBreakdownCard.rowKey(_groceriesId)));
    await tester.pumpAndSettle();
    expect(find.byType(CategoryBreakdownScreen), findsOneWidget);
    expect(find.textContaining(_money(1250, 'USD')), findsWidgets);
    expect(find.textContaining('₽'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('«Аналитика» открыта с рублями, потом основная USD: без ошибки, '
      'итоги в долларах; экран категории - тоже в долларах', (tester) async {
    await _pumpApp(tester);
    await _openTab(tester, 'Аналитика');
    expect(find.textContaining('₽'), findsWidgets);

    await _settings.setMainCurrency(_usd);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining(_money(1250, 'USD')), findsWidgets);
    expect(find.textContaining('₽'), findsNothing);

    await tester.ensureVisible(
      find.byKey(CategoryBreakdownCard.rowKey(_groceriesId)),
    );
    await tester.tap(find.byKey(CategoryBreakdownCard.rowKey(_groceriesId)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(CategoryBreakdownScreen), findsOneWidget);
    expect(find.textContaining('₽'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('основная USD: «Баланс» - сумма в долларах первой строкой, '
      'новый счёт по умолчанию в долларах', (tester) async {
    await _pumpApp(tester);
    await _openTab(tester, 'Баланс');
    // Основная RUB: первая строка - рубли, доллары - второй строкой.
    expect(
      tester.widget<Text>(find.byKey(AccountsSection.totalKey)).data,
      '+${_money(100000, 'RUB')}',
    );

    await _settings.setMainCurrency(_usd);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(AccountsSection.totalKey)).data,
      '+${_money(5000, 'USD')}',
    );
    expect(find.byKey(const ValueKey('accounts-total-RUB')), findsOneWidget);

    await tester.ensureVisible(find.byKey(AccountsSection.addButtonKey));
    await tester.tap(find.byKey(AccountsSection.addButtonKey));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byKey(AccountFormScreen.currencyRowKey),
        matching: find.text(accountFormCurrencyValue(_usd)),
      ),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
