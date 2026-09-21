import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/settings/domain/settings_repository.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

/// Хранилище в памяти; может «ломаться» на чтении и/или записи.
class _FakeSettingsRepository implements SettingsRepository {
  _FakeSettingsRepository({this.failRead = false, this.failWrite = false});

  final Map<String, String> data = {};
  bool failRead;
  bool failWrite;
  int writes = 0;

  @override
  Future<String?> read(String key) async {
    if (failRead) throw StateError('read failed');
    return data[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writes++;
    if (failWrite) throw StateError('write failed');
    data[key] = value;
  }
}

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

  test('преобразование строки: три значения туда и обратно', () {
    for (final mode in ThemeMode.values) {
      expect(themeModeFromStored(themeModeToStored(mode)), mode);
    }
    expect(themeModeToStored(ThemeMode.system), 'system');
    expect(themeModeToStored(ThemeMode.light), 'light');
    expect(themeModeToStored(ThemeMode.dark), 'dark');
  });

  test('неизвестная, пустая и null-строка дают «как в системе»', () {
    expect(themeModeFromStored(null), ThemeMode.system);
    expect(themeModeFromStored(''), ThemeMode.system);
    expect(themeModeFromStored('DARK'), ThemeMode.system);
    expect(themeModeFromStored('blue'), ThemeMode.system);
  });

  test('attach применяет сохранённую тему и уведомляет', () async {
    final repo = _FakeSettingsRepository()..data[themeModeSettingKey] = 'dark';
    final controller = AppSettingsController();
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    await controller.attach(repo);

    expect(controller.themeMode, ThemeMode.dark);
    expect(notifications, 1);
    // Чтение не должно ничего писать обратно.
    expect(repo.writes, 0);
  });

  test('setThemeMode после attach пишет значение в хранилище', () async {
    final repo = _FakeSettingsRepository();
    final controller = AppSettingsController();
    addTearDown(controller.dispose);
    await controller.attach(repo);

    controller.setThemeMode(ThemeMode.light);
    await Future<void>.delayed(Duration.zero);

    expect(repo.data[themeModeSettingKey], 'light');
  });

  test('ошибка чтения: тема остаётся прежней, исключения нет', () async {
    final controller = AppSettingsController();
    addTearDown(controller.dispose);

    await controller.attach(_FakeSettingsRepository(failRead: true));

    expect(controller.themeMode, ThemeMode.system);
  });

  test('ошибка записи не откатывает выбор и не падает', () async {
    final repo = _FakeSettingsRepository(failWrite: true);
    final controller = AppSettingsController();
    addTearDown(controller.dispose);
    await controller.attach(repo);

    final errors = <Object>[];
    await runZonedGuarded(() async {
      controller.setThemeMode(ThemeMode.dark);
      await Future<void>.delayed(Duration.zero);
    }, (error, _) => errors.add(error));

    expect(repo.writes, 1);
    expect(controller.themeMode, ThemeMode.dark);
    // Необработанных ошибок в зоне не появилось.
    expect(errors, isEmpty);
  });
}
