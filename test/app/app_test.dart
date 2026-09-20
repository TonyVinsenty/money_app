import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/app/app_tabs.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

import '../support/in_memory_database.dart';

void main() {
  test('defaultAppTabs: пять вкладок по порядку, список неизменяемый', () {
    expect(defaultAppTabs.map((tab) => tab.label).toList(), [
      'Главная',
      'История',
      'Аналитика',
      'Баланс',
      'Настройки',
    ]);
    expect(
      () => defaultAppTabs.add(defaultAppTabs.first),
      throwsUnsupportedError,
    );
    expect(defaultAppTabs.removeLast, throwsUnsupportedError);
  });

  testWidgets('MoneyApp показывает пять вкладок и содержимое «Главной»', (
    tester,
  ) async {
    final settings = AppSettingsController();
    addTearDown(settings.dispose);

    await tester.pumpWidget(
      MoneyApp(settings: settings, openDatabase: openInMemoryDatabase),
    );
    // Первый кадр — загрузка; второй — база открылась, показаны вкладки.
    await tester.pump();

    final bar = find.byType(NavigationBar);
    for (final label in [
      'Главная',
      'История',
      'Аналитика',
      'Баланс',
      'Настройки',
    ]) {
      expect(
        find.descendant(of: bar, matching: find.text(label)),
        findsOneWidget,
      );
    }
    expect(
      find.text('Здесь будут кнопки «+» и «−» и диаграмма расходов за месяц'),
      findsOneWidget,
    );
  });

  testWidgets('смена themeMode у контроллера меняет яркость темы', (
    tester,
  ) async {
    final settings = AppSettingsController();
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MoneyApp(settings: settings, openDatabase: openInMemoryDatabase),
    );
    await tester.pump();

    Brightness currentBrightness() =>
        Theme.of(tester.element(find.byType(Scaffold))).brightness;

    settings.setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(currentBrightness(), Brightness.dark);

    settings.setThemeMode(ThemeMode.light);
    await tester.pumpAndSettle();
    expect(currentBrightness(), Brightness.light);
  });
}
