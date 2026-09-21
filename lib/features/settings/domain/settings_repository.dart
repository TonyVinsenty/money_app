/// Ключ настройки «тема оформления». Значения: `system`, `light`, `dark`.
const themeModeSettingKey = 'theme_mode';

/// Хранилище настроек «ключ — значение» (ADR 0002: интерфейс в `domain`,
/// реализация в `data`). Значения — строки; что они значат, решает вызывающий.
abstract interface class SettingsRepository {
  /// Значение настройки [key] или `null`, если её ещё не записывали.
  Future<String?> read(String key);

  /// Записывает [value] в настройку [key]: создаёт или перезаписывает.
  Future<void> write(String key, String value);
}
