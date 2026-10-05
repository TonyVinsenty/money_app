import 'dart:math' as math;

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart' show AppScopeHost;
import 'package:money_app/app/app_shell.dart';
import 'package:money_app/app/app_tabs.dart';
import 'package:money_app/app/browse_controller.dart';
import 'package:money_app/app/browse_scope.dart';
import 'package:money_app/app/open_and_seed_database.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/donut_chart.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/history_view.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../support/fake_id_generator.dart';
import '../support/fixed_clock.dart';
import '../support/in_memory_database.dart';

/// Переход с «Главной» в «Историю» по сектору и строке легенды: на настоящей
/// базе в памяти, через вкладки приложения.
late AppDatabase _db;

Future<void> _put(FixedClock clock, String category, int minor) async {
  final row =
      await (_db.select(_db.categories)
            ..where((c) => c.name.equals(category) & c.kind.equals('expense')))
          .getSingle();
  await DriftTransactionsRepository(_db, clock: clock).add(
    Transaction(
      id: 'tx-$category',
      type: TransactionType.expense,
      amount: Money.fromMinor(minor, 'RUB'),
      occurredOn: DateOnly(2026, 9, 5),
      occurredAt: DateTime(2026, 9, 5, 12).toUtc(),
      categoryId: row.id,
    ),
  );
}

/// По умолчанию: Продукты 60 %, Транспорт 30 %, Кафе 7 %, «Остальное»
/// (Связь и Подарки) 3 %.
const _basic = {
  'Продукты': 60000,
  'Транспорт': 30000,
  'Кафе': 7000,
  'Связь': 1500,
  'Подарки': 1500,
};

/// Шесть секторов: три в легенде, «Ещё 4 категории» (Дом, Одежда и «Остальное»
/// из Связи и Подарков).
const _many = {
  'Продукты': 50000,
  'Транспорт': 20000,
  'Кафе': 10000,
  'Дом': 5000,
  'Одежда': 5000,
  'Связь': 1000,
  'Подарки': 1000,
};

Future<void> _pumpApp(
  WidgetTester tester, {
  Map<String, int> amounts = _basic,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final clock = FixedClock(DateTime(2026, 9, 20, 15, 30));
  final settings = AppSettingsController();
  addTearDown(settings.dispose);
  _db = await openAndSeedDatabase(
    openInMemoryDatabase,
    idGenerator: FakeIdGenerator(prefix: 'seed'),
    clock: clock,
  );
  for (final e in amounts.entries) {
    await _put(clock, e.key, e.value);
  }
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

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await _db.close();
}

BrowseController _browse(WidgetTester tester) =>
    BrowseScope.of(tester.element(find.byType(AppShell)));

int _tab(WidgetTester tester) =>
    BrowseScope.selectedTabOf(tester.element(find.byType(AppShell))).value;

/// Точка кольца на [turn] оборота по часовой стрелке от «12 часов».
Offset _ringPoint(WidgetTester tester, double turn) {
  final rect = tester.getRect(find.byType(DonutChart));
  final radius = rect.width / 2 - 2 - rect.width * 0.08;
  final angle = turn * 2 * math.pi;
  return rect.center +
      Offset(radius * math.sin(angle), -radius * math.cos(angle));
}

/// Сумма расходов сентября по именам категорий [names] (из набора [amounts]).
int _sum(Map<String, int> amounts, Iterable<String> names) =>
    names.fold(0, (sum, n) => sum + amounts[n]!);

/// Имена категорий, по которым в фильтре есть операции сентября.
Future<Set<String>> _filterNames(BrowseController browse) async {
  final ids = browse.historyFilter.expenseCategoryIds!;
  final rows = await (_db.select(
    _db.categories,
  )..where((c) => c.id.isIn(ids))).get();
  return {for (final r in rows) r.name};
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  void expectHistory(WidgetTester tester) {
    expect(_tab(tester), historyTabIndex);
    // Один маршрут в стеке: новый экран поверх вкладок не открывался.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(navigator.canPop(), isFalse);
    expect(_browse(tester).month, monthRange(DateOnly(2026, 9, 20)));
  }

  testWidgets('сектор «Продукты» ведёт в «Историю»; «Назад» на «Главную», '
      'фильтр остаётся', (tester) async {
    await _pumpApp(tester);

    await tester.tapAt(_ringPoint(tester, 0.3));
    await tester.pumpAndSettle();
    expectHistory(tester);
    expect(find.text('Фильтр: Расходы · Продукты'), findsOneWidget);
    expect(find.text('Продукты'), findsOneWidget);
    expect(find.text('Транспорт'), findsNothing);
    expect(_browse(tester).historySort, HistorySort.newestFirst);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_tab(tester), 0);
    expect(find.text('Расходы по категориям'), findsOneWidget);
    expect(_browse(tester).historyFilter.isActive, isTrue);
    await _finish(tester);
  });

  testWidgets('палец переезжает с сектора на сектор: фильтр по категории '
      'под пальцем при отпускании', (tester) async {
    await _pumpApp(tester);

    // Точки 0.3 и 0.7 на одной высоте: движение горизонтальное, прокрутку не начинает.
    final g = await tester.startGesture(_ringPoint(tester, 0.3));
    await tester.pump();
    await g.moveTo(_ringPoint(tester, 0.7));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expectHistory(tester);
    expect(find.text('Фильтр: Расходы · Транспорт'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('палец унесён за кольцо: ничего не происходит', (tester) async {
    await _pumpApp(tester);

    final g = await tester.startGesture(_ringPoint(tester, 0.3));
    await tester.pump();
    await g.moveTo(_ringPoint(tester, 0.7));
    await tester.pump();
    final rect = tester.getRect(find.byType(DonutChart));
    await g.moveTo(Offset(rect.center.dx, _ringPoint(tester, 0.7).dy));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(_tab(tester), 0);
    expect(_browse(tester).historyFilter.isActive, isFalse);
    await _finish(tester);
  });

  testWidgets('строка легенды ведёт в «Историю»; другая категория заменяет '
      'фильтр, сортировка не меняется', (tester) async {
    await _pumpApp(tester);
    _browse(tester).setHistorySort(HistorySort.largestFirst);

    // Легенда под кольцом: на низком экране до неё нужно прокрутить.
    await tester.ensureVisible(find.text('Транспорт'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Транспорт'));
    await tester.pumpAndSettle();
    expectHistory(tester);
    expect(find.text('Фильтр: Расходы · Транспорт'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Кафе'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Кафе'));
    await tester.pumpAndSettle();
    expectHistory(tester);
    expect(find.text('Фильтр: Расходы · Кафе'), findsOneWidget);
    expect(find.text('Транспорт'), findsNothing);
    expect(_browse(tester).historySort, HistorySort.largestFirst);
    await _finish(tester);
  });

  testWidgets('«Остальное»: сектор и строка ведут на категории группы, '
      'сумма списка равна сумме сектора', (tester) async {
    await _pumpApp(tester);

    await tester.tapAt(_ringPoint(tester, 0.985));
    await tester.pumpAndSettle();
    expectHistory(tester);
    expect(find.text('Фильтр: Расходы · Связь, Подарки'), findsOneWidget);
    expect(find.text('Связь'), findsOneWidget);
    expect(find.text('Подарки'), findsOneWidget);
    expect(find.text('Продукты'), findsNothing);
    final names = await _filterNames(_browse(tester));
    expect(_sum(_basic, names), 3000);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Остальное'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Остальное'));
    await tester.pumpAndSettle();
    expectHistory(tester);
    expect(find.text('Фильтр: Расходы · Связь, Подарки'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('«Ещё N категорий» ведёт на категории вне первых трёх, сумма '
      'списка равна сумме элемента', (tester) async {
    await _pumpApp(tester, amounts: _many);

    await tester.ensureVisible(find.text('Ещё 4 категории'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ещё 4 категории'));
    await tester.pumpAndSettle();
    expectHistory(tester);
    expect(find.text('Фильтр: Расходы · 4 категории'), findsOneWidget);
    final names = await _filterNames(_browse(tester));
    expect(names, {'Дом', 'Одежда', 'Связь', 'Подарки'});
    expect(_sum(_many, names), 12000);
    expect(find.text('Продукты'), findsNothing);
    await _finish(tester);
  });

  testWidgets('касание мимо кольца и центр кольца ничего не меняют', (
    tester,
  ) async {
    await _pumpApp(tester);

    await tester.tapAt(tester.getCenter(find.byType(DonutChart)));
    await tester.pumpAndSettle();
    expect(_tab(tester), 0);
    expect(_browse(tester).historyFilter.isActive, isFalse);
    await _finish(tester);
  });
}
