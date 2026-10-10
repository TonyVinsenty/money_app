/// Ключ настройки «тема оформления». Значения: `system`, `light`, `dark`.
const themeModeSettingKey = 'theme_mode';

/// Ключ настройки «строка «Баланс» на Главной». Значения: `allTime`,
/// `accounts`, `none`.
const homeBalanceLineSettingKey = 'home_balance_line';

/// Ключ настройки «основная валюта». Значение — код обычной валюты из
/// каталога (`RUB`, `USD`).
const mainCurrencySettingKey = 'main_currency';

/// Ключ настройки «основной счёт». Значение — id счёта.
const defaultAccountSettingKey = 'default_account_id';

/// Ключ настройки «последняя выгрузка CSV». Значение — локальный день
/// ГГГГММДД строкой (например, `20261007`).
const lastExportDaySettingKey = 'last_export_day';

/// Хранилище настроек «ключ — значение» (ADR 0002: интерфейс в `domain`,
/// реализация в `data`). Значения — строки; что они значат, решает вызывающий.
abstract interface class SettingsRepository {
  /// Значение настройки [key] или `null`, если её ещё не записывали.
  Future<String?> read(String key);

  /// Записывает [value] в настройку [key]: создаёт или перезаписывает.
  Future<void> write(String key, String value);
}
