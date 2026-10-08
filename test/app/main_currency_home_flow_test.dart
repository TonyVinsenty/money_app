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
import 'package:money_app/core/ui/amount_field.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/home/presentation/month_chart_card.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/edit/edit_transaction_screen.dart';

import '../support/fake_id_generator.dart';
import '../support/fixed_clock.dart';
import '../support/in_memory_database.dart';
import '../support/settle_database.dart';

/// Основная валюта (шаг 5.10n): быстрый ввод, «Главная» и правка операции на
/// настоящей базе в памяти. «История» — в шаге 5.10o (отдельный файл).
late AppDatabase _db;
late FixedClock _clock;
late AppSettingsController _settings;

CurrencyInfo get _usd => catalogCurrency('USD')!;
CurrencyInfo get _jpy => catalogCurrency('JPY')!;
CurrencyInfo get _rub => catalogCurrency('RUB')!;

final _minus = String.fromCharCode(0x2212);

String _money(int minor, String code) =>
    formatMoney(Money.fromMinor(minor, code));

Finder _inExpense(String text) => find.descendant(
  of: find.byKey(const ValueKey('month-summary-expense')),
  matching: find.text(text),
);

Finder _inRing(String text) =>
    find.descendant(of: find.byType(MonthChartCard), matching: find.text(text));

final _expenseEmpty = find.descendant(
  of: find.byKey(const ValueKey('month-summary-expense')),
  matching: find.text('Пока нет'),
);

/// Рублёвый расход (350 ₽) в «Продуктах» кладётся до первого кадра.
Future<void> _pumpApp(WidgetTester tester) async {
  _clock = FixedClock(DateTime(2026, 9, 20, 15, 30));
  _settings = AppSettingsController();
  addTearDown(_settings.dispose);
  _db = await openAndSeedDatabase(
    openInMemoryDatabase,
    idGenerator: FakeIdGenerator(prefix: 'seed'),
    clock: _clock,
  );
  addTearDown(_db.close);
  final category =
      await (_db.select(
            _db.categories,
          )..where((c) => c.name.equals('Продукты') & c.kind.equals('expense')))
          .getSingle();
  await DriftTransactionsRepository(_db, clock: _clock).add(
    Transaction(
      id: 'seed-tx',
      type: TransactionType.expense,
      amount: Money.fromMinor(35000, 'RUB'),
      occurredOn: DateOnly(2026, 9, 20),
      occurredAt: DateTime(2026, 9, 20, 15, 30).toUtc(),
      categoryId: category.id,
      note: 'молоко',
    ),
  );
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
        child: BrowseHost(child: AppShell(tabs: defaultAppTabs)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _addExpense(WidgetTester tester, String amount) async {
  await tester.tap(find.text('Расход'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), amount);
  await tester.tap(find.widgetWithText(FilledButton, 'Далее'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Продукты'));
  await settleDatabase(tester);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  testWidgets('основная USD: рублёвых операций на «Главной» не видно, расход '
      '12,50 \$ попадает в итог и кольцо; вернули RUB - прежние итоги', (
    tester,
  ) async {
    await _pumpApp(tester);
    expect(_inExpense('$_minus${_money(35000, 'RUB')}'), findsOneWidget);

    _settings.setMainCurrency(_usd);
    await tester.pumpAndSettle();
    expect(_expenseEmpty, findsOneWidget);
    expect(_inRing(_money(0, 'USD')), findsOneWidget);

    await _addExpense(tester, '12,50');
    final usd = _money(1250, 'USD');
    expect(_inExpense('$_minus$usd'), findsOneWidget);
    // Баланс в центре кольца: доходов нет, поэтому минус расход.
    expect(_inRing('$_minus$usd'), findsOneWidget);
    expect(find.text('$_minus${_money(35000, 'RUB')}'), findsNothing);

    final saved = await _db.select(_db.transactions).get();
    expect(saved.where((t) => t.currency == 'USD').single.amountMinor, 1250);

    _settings.setMainCurrency(_rub);
    await tester.pumpAndSettle();
    expect(_inExpense('$_minus${_money(35000, 'RUB')}'), findsOneWidget);
    expect(find.text('$_minus$usd'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('основная JPY: поле без запятой, сумма сохраняется в иенах', (
    tester,
  ) async {
    await _pumpApp(tester);
    _settings.setMainCurrency(_jpy);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Расход'));
    await tester.pumpAndSettle();
    final field = find.descendant(
      of: find.byType(AmountField),
      matching: find.byType(TextField),
    );
    // Запятая и точка не вводятся: ввод с дробной частью отклоняется целиком.
    await tester.enterText(field, '1500,5');
    expect(tester.widget<TextField>(field).controller!.text, isEmpty);
    await tester.enterText(field, '1500');
    await tester.tap(find.widgetWithText(FilledButton, 'Далее'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Продукты'));
    await settleDatabase(tester);

    final saved = await _db.select(_db.transactions).get();
    final yen = saved.singleWhere((t) => t.currency == 'JPY');
    expect(yen.amountMinor, 1500);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'основная USD: правка долларовой операции из «Истории» сохраняет USD',
    (tester) async {
      await _pumpApp(tester);
      final category =
          await (_db.select(_db.categories)..where(
                (c) => c.name.equals('Продукты') & c.kind.equals('expense'),
              ))
              .getSingle();
      await DriftTransactionsRepository(_db, clock: _clock).add(
        Transaction(
          id: 'usd-tx',
          type: TransactionType.expense,
          amount: Money.fromMinor(1250, 'USD'),
          occurredOn: DateOnly(2026, 9, 20),
          occurredAt: DateTime(2026, 9, 20, 16).toUtc(),
          categoryId: category.id,
          note: 'кофе',
        ),
      );
      _settings.setMainCurrency(_usd);
      await tester.pumpAndSettle();

      // В «Истории» при основной USD видна долларовая операция.
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('История'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('кофе'));
      await tester.pumpAndSettle();
      expect(find.byType(EditTransactionScreen), findsOneWidget);

      final field = find.descendant(
        of: find.byType(AmountField),
        matching: find.byType(TextField),
      );
      await tester.enterText(field, '40,25');
      await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
      await tester.pumpAndSettle();

      final row = await (_db.select(
        _db.transactions,
      )..where((t) => t.id.equals('usd-tx'))).getSingle();
      expect(row.currency, 'USD');
      expect(row.amountMinor, 4025);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
