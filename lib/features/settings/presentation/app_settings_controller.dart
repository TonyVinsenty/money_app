import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:money_app/core/time/date_only.dart';
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

/// Строка для записи в базу: день как ГГГГММДД.
String lastExportDayToStored(DateOnly day) => day.toInt().toString();

/// Обратное преобразование. Пусто, не число или несуществующий день — `null`
/// («выгрузки ещё не было»): одна странная строка не должна ронять приложение.
DateOnly? lastExportDayFromStored(String? value) {
  if (value == null) return null;
  final number = int.tryParse(value);
  if (number == null) return null;
  try {
    return DateOnly.fromInt(number);
  } on ArgumentError {
    return null;
  }
}

/// Настройки приложения, которые можно менять на лету.
///
/// Контроллер создаётся до открытия базы (тема нужна уже экрану загрузки),
/// поэтому хранилище подключается позже через [attach]. До этого и при
/// ошибках записи выбор живёт только в памяти на текущий запуск.
class AppSettingsController extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  DateOnly? _lastExportDay;
  SettingsRepository? _repository;

  ThemeMode get themeMode => _themeMode;

  /// День последней выгрузки CSV или `null`, если её ещё не было.
  DateOnly? get lastExportDay => _lastExportDay;

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
    try {
      final stored = await repository.read(lastExportDaySettingKey);
      if (_repository != repository) return;
      final day = lastExportDayFromStored(stored);
      if (day != _lastExportDay) {
        _lastExportDay = day;
        notifyListeners();
      }
    } catch (error) {
      debugPrint('Не удалось прочитать день выгрузки из настроек: $error');
    }
  }

  /// Запоминает день выгрузки сразу, запись в базу идёт в фоне; ошибка записи
  /// только попадает в лог.
  void setLastExportDay(DateOnly day) {
    if (day == _lastExportDay) return;
    _lastExportDay = day;
    notifyListeners();
    unawaited(_persistLastExportDay(day));
  }

  Future<void> _persistLastExportDay(DateOnly day) async {
    final repository = _repository;
    if (repository == null) return;
    try {
      await repository.write(
        lastExportDaySettingKey,
        lastExportDayToStored(day),
      );
    } catch (error) {
      debugPrint('Не удалось сохранить день выгрузки: $error');
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
