import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:money_app/features/settings/domain/settings_repository.dart';

/// Строка для записи в базу; значения — часть формата хранения, не менять.
String themeModeToStored(ThemeMode mode) => switch (mode) {
  ThemeMode.system => 'system',
  ThemeMode.light => 'light',
  ThemeMode.dark => 'dark',
};

/// Обратное преобразование. Пусто, неизвестно или испорчено — «как в системе»:
/// приложение не должно падать из-за одной странной строки в настройках.
ThemeMode themeModeFromStored(String? value) => switch (value) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

/// Настройки приложения, которые можно менять на лету.
///
/// Контроллер создаётся до открытия базы (тема нужна уже экрану загрузки),
/// поэтому хранилище подключается позже через [attach]. До этого и при
/// ошибках записи выбор живёт только в памяти на текущий запуск.
class AppSettingsController extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  SettingsRepository? _repository;

  ThemeMode get themeMode => _themeMode;

  /// Подключает хранилище и применяет сохранённую в нём тему. Ошибка чтения
  /// не пробрасывается: тема остаётся прежней («как в системе» при старте).
  Future<void> attach(SettingsRepository repository) async {
    _repository = repository;
    try {
      final stored = await repository.read(themeModeSettingKey);
      // Пока читали, подключили другое хранилище: этот результат уже старый.
      if (_repository != repository) return;
      _apply(themeModeFromStored(stored));
    } catch (error) {
      debugPrint('Не удалось прочитать тему из настроек: $error');
    }
  }

  /// Меняет тему сразу, а запись в базу идёт в фоне: ошибка записи не
  /// откатывает выбор и не роняет приложение, а только попадает в лог.
  void setThemeMode(ThemeMode value) {
    if (value == _themeMode) return;
    _apply(value);
    unawaited(_persist(value));
  }

  void _apply(ThemeMode value) {
    if (value == _themeMode) return;
    _themeMode = value;
    notifyListeners();
  }

  Future<void> _persist(ThemeMode value) async {
    final repository = _repository;
    if (repository == null) return;
    try {
      await repository.write(themeModeSettingKey, themeModeToStored(value));
    } catch (error) {
      debugPrint('Не удалось сохранить тему: $error');
    }
  }
}
