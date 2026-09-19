import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

void main() {
  test('по умолчанию тема следует системной', () {
    final controller = AppSettingsController();
    addTearDown(controller.dispose);

    expect(controller.themeMode, ThemeMode.system);
  });

  test('setThemeMode меняет значение и уведомляет слушателя один раз', () {
    final controller = AppSettingsController();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.setThemeMode(ThemeMode.dark);

    expect(controller.themeMode, ThemeMode.dark);
    expect(notifications, 1);
  });

  test('повторная установка того же значения не уведомляет', () {
    final controller = AppSettingsController();
    addTearDown(controller.dispose);
    controller.setThemeMode(ThemeMode.dark);
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.setThemeMode(ThemeMode.dark);

    expect(notifications, 0);
  });
}
