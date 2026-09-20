import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter/material.dart' show ThemeMode;

/// Настройки приложения, которые можно менять на лету.
///
/// Известное ограничение: выбор темы живёт только в памяти и после
/// перезапуска приложения сбрасывается на «как в системе». Это не баг:
/// хранилище настроек (таблица в БД) появится на этапах 2 и 6.
class AppSettingsController extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  void setThemeMode(ThemeMode value) {
    if (value == _themeMode) return;
    _themeMode = value;
    notifyListeners();
  }
}
