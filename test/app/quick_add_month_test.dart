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
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/date_chip.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

import '../support/fake_id_generator.dart';
import '../support/fixed_clock.dart';
import '../support/in_memory_database.dart';
import '../support/settle_database.dart';

/// Сквозной путь сохранения на настоящей базе в памяти: «Главная» -> «Расход»
/// -> сумма -> категория -> запись в таблице и сообщение с «Отменить».
///
/// Собирается так же, как `MoneyApp`, только с фиксированными часами и
/// понятными id (`MoneyApp` берёт настоящие часы).
final _clock = FixedClock(DateTime(2026, 10, 4, 15, 30));

late AppDatabase _db;

Future<void> _pumpApp(WidgetTester tester, {double textScale = 1}) async {
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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),

      home: AppScopeHost(
        database: _db,
        settings: settings,
        clock: _clock,
        idGenerator: FakeIdGenerator(prefix: 'tx'),
        child: BrowseHost(child: AppShell(tabs: defaultAppTabs)),
      ),
    ),
  );
  await tester.pump();
}

BrowseController _browse(WidgetTester tester) =>
    BrowseScope.of(tester.element(find.byType(AppShell)));

Future<void> _addExpense(WidgetTester tester, {String? pickDay}) async {
  await tester.tap(find.text('Расход'));
  await tester.pumpAndSettle();
  if (pickDay != null) {
    await tester.tap(find.byType(DateChip));
    await tester.pumpAndSettle();
    if (pickDay == '15') {
      await tester.tap(find.byTooltip('Предыдущий месяц').last);
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text(pickDay));
    await tester.tap(find.text('ОК'));
    await tester.pumpAndSettle();
  }
  await tester.enterText(find.byType(TextField), '350');
  await tester.tap(find.widgetWithText(FilledButton, 'Далее'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Продукты'));
  await settleDatabase(tester);
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

  testWidgets('на «Главной» август, добавили расход сегодня: текущий месяц', (
    tester,
  ) async {
    await _pumpApp(tester);
    _browse(tester).showMonthOf(DateOnly(2026, 8, 10));
    await tester.pumpAndSettle();
    expect(find.text('Август 2026'), findsOneWidget);

    await _addExpense(tester);
    expect(find.text('Октябрь 2026'), findsOneWidget);
    expect(_browse(tester).month, monthRange(DateOnly(2026, 10, 4)));
    await _finish(tester);
  });

  testWidgets('добавили с датой в сентябре: «Главная» показывает сентябрь', (
    tester,
  ) async {
    await _pumpApp(tester);
    await _addExpense(tester, pickDay: '15');
    expect(find.text('Сентябрь 2026'), findsOneWidget);
    expect(_browse(tester).month, monthRange(DateOnly(2026, 9, 15)));
    await _finish(tester);
  });

  testWidgets('«Отменить» месяц не возвращает', (tester) async {
    await _pumpApp(tester);
    _browse(tester).showMonthOf(DateOnly(2026, 8, 10));
    await tester.pumpAndSettle();

    await _addExpense(tester);
    expect(find.text('Октябрь 2026'), findsOneWidget);
    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();
    expect(find.text('Октябрь 2026'), findsOneWidget);
    expect(_browse(tester).month, monthRange(DateOnly(2026, 10, 4)));
    await _finish(tester);
  });
}
