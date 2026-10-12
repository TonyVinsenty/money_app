import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart' show AppScopeHost;
import 'package:money_app/app/app_shell.dart';
import 'package:money_app/app/app_tabs.dart';
import 'package:money_app/app/browse_scope.dart';
import 'package:money_app/app/open_and_seed_database.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

import 'extreme_data.dart';
import 'fake_id_generator.dart';
import 'in_memory_database.dart';
import 'settle_database.dart';

/// Приложение целиком на наборе крайних данных ([seedExtremeData]): телефон
/// 360 × 780 dp, шрифт [scale], «сегодня» — [clock] (по умолчанию
/// [extremeClock]).
Future<void> pumpExtremeApp(
  WidgetTester tester,
  double scale, {
  Clock? clock,
}) async {
  final today = clock ?? extremeClock;
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
        clock: today,
        idGenerator: FakeIdGenerator(prefix: 'tx'),
        child: BrowseHost(child: AppShell(tabs: defaultAppTabs)),
      ),
    ),
  );
  await settleDatabase(tester);
}

/// Вкладка нижней панели с подписью [label].
Future<void> openExtremeTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await settleDatabase(tester);
}

/// Прокручивает экран до конца и обратно, проверяя после каждого шага, что
/// раскладка не сообщила о переполнении или другой ошибке.
Future<void> scrollThrough(WidgetTester tester, String where) async {
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
