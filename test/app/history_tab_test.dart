import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart' show AppScopeHost;
import 'package:money_app/app/app_shell.dart';
import 'package:money_app/app/app_tabs.dart';
import 'package:money_app/app/open_and_seed_database.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/categories/data/categories_repository_impl.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../support/fake_id_generator.dart';
import '../support/fixed_clock.dart';
import '../support/in_memory_database.dart';
import '../support/settle_database.dart';

/// Вкладка «История» на настоящей базе в памяти: собрана так же, как
/// `MoneyApp`, только с фиксированными часами (сегодня 20 сентября 2026).
final _clock = FixedClock(DateTime(2026, 9, 20, 15, 30));
final _minus = String.fromCharCode(0x2212);

late AppDatabase _db;

Future<void> _pumpApp(WidgetTester tester) async {
  final settings = AppSettingsController();
  addTearDown(settings.dispose);
  _db = await openAndSeedDatabase(
    openInMemoryDatabase,
    idGenerator: FakeIdGenerator(prefix: 'seed'),
    clock: _clock,
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
        settings: settings,
        clock: _clock,
        idGenerator: FakeIdGenerator(prefix: 'tx'),
        child: AppShell(tabs: defaultAppTabs),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Future<String> _expenseCategoryId(String name) async {
  final row = await (_db.select(
    _db.categories,
  )..where((c) => c.name.equals(name) & c.kind.equals('expense'))).getSingle();
  return row.id;
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await _db.close();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  testWidgets('операций нет: вкладка показывает пустое состояние', (
    tester,
  ) async {
    await _pumpApp(tester);
    await _openTab(tester, 'История');

    expect(find.text('Операций пока нет'), findsOneWidget);
    expect(find.text('Здесь будет список доходов и расходов'), findsNothing);
    await _finish(tester);
  });

  testWidgets(
    'расход, сохранённый быстрым вводом, сам появляется в «Истории»',
    (tester) async {
      await _pumpApp(tester);
      await _openTab(tester, 'История');
      expect(find.text('Операций пока нет'), findsOneWidget);

      // «Главная» -> «Расход» -> сумма -> категория.
      await _openTab(tester, 'Главная');
      await tester.tap(find.text('Расход'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '350');
      await tester.tap(find.widgetWithText(FilledButton, 'Далее'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Продукты'));
      await settleDatabase(tester);

      // Вкладка уже открывалась: список обновился сам, без «обновить».
      await _openTab(tester, 'История');
      final amount = '$_minus${formatMoney(Money.fromMinor(35000, 'RUB'))}';
      expect(find.text('Операций пока нет'), findsNothing);
      expect(find.text('Сегодня'), findsOneWidget);
      expect(find.text('Продукты'), findsOneWidget);
      expect(find.text(amount), findsOneWidget);

      // «Отменить» на «Главной»: запись пропадает и из «Истории».
      await _openTab(tester, 'Главная');
      await tester.tap(find.text('Отменить'));
      await tester.pumpAndSettle();
      await _openTab(tester, 'История');
      expect(find.text('Операций пока нет'), findsOneWidget);
      await _finish(tester);
    },
  );

  testWidgets('расход с нулевой суммой сохраняется, виден в «Истории» и не '
      'входит в итог «Главной»', (tester) async {
    await _pumpApp(tester);
    await tester.pumpAndSettle();
    final emptyExpenses = find.descendant(
      of: find.byKey(const ValueKey('month-summary-expense')),
      matching: find.text('Пока нет'),
    );
    expect(emptyExpenses, findsOneWidget);

    // «Главная» -> «Расход» -> сумма 0 -> категория.
    await tester.tap(find.text('Расход'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0');
    await tester.tap(find.widgetWithText(FilledButton, 'Далее'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Продукты'));
    await settleDatabase(tester);

    final zero = formatMoney(Money.zero('RUB'));
    expect(find.text('Сохранено: расход $zero · Продукты'), findsOneWidget);
    // Ноль в итог месяца не входит: строка расходов остаётся пустой.
    expect(emptyExpenses, findsOneWidget);
    expect(find.text('Сентябрь 2026'), findsOneWidget);

    // В «Истории» операция есть, с нулевой суммой.
    await _openTab(tester, 'История');
    expect(find.text('Операций пока нет'), findsNothing);
    expect(find.text('Продукты'), findsOneWidget);
    expect(find.text('$_minus$zero'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('архивная категория показывает своё имя, новые сверху', (
    tester,
  ) async {
    await _pumpApp(tester);
    final cafe = await _expenseCategoryId('Кафе');
    final food = await _expenseCategoryId('Продукты');
    final repo = DriftTransactionsRepository(_db, clock: _clock);
    Transaction tx(String id, DateOnly day, String categoryId, int minor) =>
        Transaction(
          id: id,
          type: TransactionType.expense,
          amount: Money.fromMinor(minor, 'RUB'),
          occurredOn: day,
          occurredAt: DateTime(day.year, day.month, day.day, 12).toUtc(),
          categoryId: categoryId,
        );
    await repo.add(tx('old', DateOnly(2026, 9, 19), cafe, 12000));
    await repo.add(tx('new', DateOnly(2026, 9, 20), food, 5000));
    await DriftCategoriesRepository(_db, clock: _clock).archive(cafe);

    await _openTab(tester, 'История');

    expect(find.text('Кафе'), findsOneWidget);
    expect(find.text('Вчера'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Продукты')).dy,
      lessThan(tester.getTopLeft(find.text('Кафе')).dy),
    );
    await _finish(tester);
  });
}
