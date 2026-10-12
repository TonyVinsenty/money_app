import 'package:drift/drift.dart' show driftRuntimeOptions;
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
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

import '../support/extreme_data.dart';
import '../support/fake_id_generator.dart';
import '../support/in_memory_database.dart';
import '../support/settle_database.dart';

/// Шаг 7.43 (К2): «Главная», «История» и четыре раздела «Аналитики» на
/// наборе крайних данных, телефон 360 dp, шрифт 100 и 200 %: ни переполнений,
/// ни исключений, в том числе при прокрутке до конца.
Future<void> _pumpApp(WidgetTester tester, double scale) async {
  tester.view.physicalSize = const Size(360, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = AppSettingsController();
  addTearDown(settings.dispose);
  late AppDatabase db;
  await tester.runAsync(() async {
    db = await openAndSeedDatabase(
      openInMemoryDatabase,
      idGenerator: FakeIdGenerator(prefix: 'seed'),
      clock: extremeClock,
    );
    await seedExtremeData(db);
  });
  addTearDown(db.close);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: MoneyApp.appLocale,
      supportedLocales: MoneyApp.supportedLocales,
      localizationsDelegates: MoneyApp.localizationsDelegates,
      onGenerateRoute: onGenerateAppRoute,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: AppScopeHost(
        database: db,
        settings: settings,
        clock: extremeClock,
        idGenerator: FakeIdGenerator(prefix: 'tx'),
        child: BrowseHost(child: AppShell(tabs: defaultAppTabs)),
      ),
    ),
  );
  await settleDatabase(tester);
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await settleDatabase(tester);
}

/// Прокручивает экран до конца и обратно, проверяя после каждого шага, что
/// раскладка не сообщила о переполнении или другой ошибке.
Future<void> _scrollThrough(WidgetTester tester, String where) async {
  expect(tester.takeException(), isNull, reason: '$where: сразу');
  for (final dy in [-400.0, 400.0]) {
    for (var i = 0; i < 20; i++) {
      await tester.dragFrom(const Offset(180, 420), Offset(0, dy));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: '$where: прокрутка');
    }
  }
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: '$where: в конце');
}

final _maxRub = formatMoney(Money.fromMinor(extremeMaxRubMinor, 'RUB'));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  for (final scale in [1.0, 2.0]) {
    final percent = '${(scale * 100).round()} %';

    testWidgets('«Главная», $percent', (tester) async {
      await _pumpApp(tester, scale);
      // Набор действительно на экране: плашка платежа на сегодня.
      expect(find.textContaining('К оплате'), findsWidgets);
      await _scrollThrough(tester, 'Главная');
    });

    testWidgets('«История», $percent', (tester) async {
      await _pumpApp(tester, scale);
      await _openTab(tester, 'История');
      expect(find.textContaining('Коммунальные'), findsWidgets);
      await _scrollThrough(tester, 'История');
    });

    testWidgets('«Аналитика», четыре раздела, $percent', (tester) async {
      await _pumpApp(tester, scale);
      await _openTab(tester, 'Аналитика');
      for (final section in [
        'Категории',
        'Динамика',
        'Сравнение',
        'Операции',
      ]) {
        final tab = find.widgetWithText(Tab, section);
        await tester.ensureVisible(tab);
        await tester.tap(tab);
        await settleDatabase(tester);
        if (section == 'Операции') {
          expect(find.textContaining(_maxRub), findsWidgets);
        }
        await _scrollThrough(tester, 'Аналитика → $section');
      }
    });
  }
}
