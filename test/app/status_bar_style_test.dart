import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/app/app_shell.dart';

import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

import '../support/in_memory_database.dart';

/// Стиль строки состояния над всем навигатором (экраны без AppBar —
/// «Баланс» и «Настройки» — получают его отсюда).
SystemUiOverlayStyle _appStyle(WidgetTester tester) {
  final region = find.ancestor(
    of: find.byType(AppShell),
    matching: find.byWidgetPredicate(
      (w) => w is AnnotatedRegion<SystemUiOverlayStyle>,
    ),
  );
  return tester
      .widget<AnnotatedRegion<SystemUiOverlayStyle>>(region.first)
      .value;
}

void main() {
  late AppSettingsController settings;

  Future<void> launch(WidgetTester tester, Brightness system) async {
    tester.platformDispatcher.platformBrightnessTestValue = system;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    settings = AppSettingsController();

    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MoneyApp(settings: settings, openDatabase: openInMemoryDatabase),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('светлая тема: тёмные значки строки состояния', (tester) async {
    await launch(tester, Brightness.light);
    final style = _appStyle(tester);
    expect(style.statusBarIconBrightness, Brightness.dark);
    expect(style.statusBarBrightness, Brightness.light);
    expect(style.statusBarColor, Colors.transparent);
  });

  testWidgets('тёмная тема: светлые значки строки состояния', (tester) async {
    await launch(tester, Brightness.dark);
    final style = _appStyle(tester);
    expect(style.statusBarIconBrightness, Brightness.light);
    expect(style.statusBarBrightness, Brightness.dark);
  });
}
