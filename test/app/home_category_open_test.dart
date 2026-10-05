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
import 'package:money_app/app/browse_scope.dart';
import 'package:money_app/app/open_and_seed_database.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/format/period_label.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/donut_chart.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/analytics/presentation/category_breakdown_screen.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../support/fake_id_generator.dart';
import '../support/fixed_clock.dart';
import '../support/in_memory_database.dart';

/// Переход с «Главной» на экран категории: на настоящей базе в памяти, через
/// маршруты приложения.
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

/// Продукты 60 %, Транспорт 30 %, Кафе 7 %, «Остальное» (Связь и Подарки) 3 %.
Future<void> _pumpApp(WidgetTester tester) async {
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
  await _put(clock, 'Продукты', 60000);
  await _put(clock, 'Транспорт', 30000);
  await _put(clock, 'Кафе', 7000);
  await _put(clock, 'Связь', 1500);
  await _put(clock, 'Подарки', 1500);
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
        child: BrowseHost(child: AppShell(tabs: defaultAppTabs)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await _db.close();
}

/// Точка кольца на [turn] оборота по часовой стрелке от «12 часов».
Offset _ringPoint(WidgetTester tester, double turn) {
  final rect = tester.getRect(find.byType(DonutChart));
  final radius = rect.width / 2 - 2 - rect.width * 0.08;
  final angle = turn * 2 * math.pi;
  return rect.center +
      Offset(radius * math.sin(angle), -radius * math.cos(angle));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  void expectBreakdown(String name) {
    expect(find.byType(CategoryBreakdownScreen), findsOneWidget);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text(name)),
      findsOneWidget,
    );
    final monthLabel = formatPeriodLabel(
      PeriodKind.month,
      monthRange(DateOnly(2026, 9, 20)),
    );
    expect(find.text(monthLabel), findsOneWidget);
  }

  testWidgets('сектор «Продукты» открывает экран категории, «Назад» '
      'возвращает на «Главную»', (tester) async {
    await _pumpApp(tester);
    expect(find.byType(CategoryBreakdownScreen), findsNothing);

    await tester.tapAt(_ringPoint(tester, 0.3));
    await tester.pumpAndSettle();
    expectBreakdown('Продукты');

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(CategoryBreakdownScreen), findsNothing);
    expect(find.text('Расходы по категориям'), findsOneWidget);
    await _finish(tester);
  });

  testWidgets('палец переезжает с сектора на сектор: открывается категория '
      'под пальцем при отпускании', (tester) async {
    await _pumpApp(tester);

    // Точки 0.3 и 0.7 на одной высоте: движение горизонтальное, прокрутку не начинает.
    final g = await tester.startGesture(_ringPoint(tester, 0.3));
    await tester.pump();
    await g.moveTo(_ringPoint(tester, 0.7));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expectBreakdown('Транспорт');
    await _finish(tester);
  });

  testWidgets('палец унесён за кольцо: ничего не открывается', (tester) async {
    await _pumpApp(tester);

    // Точки 0.3 и 0.7 на одной высоте: движение горизонтальное, прокрутку не начинает.
    final g = await tester.startGesture(_ringPoint(tester, 0.3));
    await tester.pump();
    await g.moveTo(_ringPoint(tester, 0.7));
    await tester.pump();
    final rect = tester.getRect(find.byType(DonutChart));
    await g.moveTo(Offset(rect.center.dx, _ringPoint(tester, 0.7).dy));
    await tester.pump();
    await g.up();
    await tester.pumpAndSettle();
    expect(find.byType(CategoryBreakdownScreen), findsNothing);
    await _finish(tester);
  });

  testWidgets('строка легенды открывает экран категории', (tester) async {
    await _pumpApp(tester);

    // Легенда под кольцом: на низком экране до неё нужно прокрутить.
    await tester.ensureVisible(find.text('Транспорт'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Транспорт'));
    await tester.pumpAndSettle();
    expectBreakdown('Транспорт');
    await _finish(tester);
  });

  testWidgets('«Остальное» и касание мимо кольца ничего не открывают', (
    tester,
  ) async {
    await _pumpApp(tester);

    await tester.tapAt(_ringPoint(tester, 0.985));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Остальное'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Остальное'));
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(find.byType(DonutChart)));
    await tester.pumpAndSettle();

    expect(find.byType(CategoryBreakdownScreen), findsNothing);
    await _finish(tester);
  });
}
