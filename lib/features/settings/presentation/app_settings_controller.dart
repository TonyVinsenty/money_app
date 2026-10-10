import 'dart:async';

import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/settings/domain/home_balance_line.dart';
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

/// Строка для записи в базу; значения — часть формата хранения, не менять.
String homeBalanceLineToStored(HomeBalanceLine line) => switch (line) {
  HomeBalanceLine.allTime => 'allTime',
  HomeBalanceLine.accounts => 'accounts',
  HomeBalanceLine.none => 'none',
};

/// Обратное преобразование. Пусто, неизвестно или испорчено — «все доходы
/// минус все расходы» (значение по умолчанию).
HomeBalanceLine homeBalanceLineFromStored(String? value) => switch (value) {
  'accounts' => HomeBalanceLine.accounts,
  'none' => HomeBalanceLine.none,
  _ => HomeBalanceLine.allTime,
};

/// Строка для записи в базу: код валюты.
String mainCurrencyToStored(CurrencyInfo currency) => currency.code;

/// Обратное преобразование. Пусто, испорчено, не из каталога или не обычная
/// валюта (крипта, своя) — рубль: основной валютой может быть только fiat.
CurrencyInfo mainCurrencyFromStored(String? value) {
  final info = value == null ? null : catalogCurrency(value);
  if (info != null && info.kind == CurrencyKind.fiat) return info;
  return _defaultMainCurrency;
}

final CurrencyInfo _defaultMainCurrency = catalogCurrency('RUB')!;

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
  CurrencyInfo _mainCurrency = _defaultMainCurrency;
  String? _defaultAccountId;
  SettingsRepository? _repository;

  ThemeMode get themeMode => _themeMode;

  HomeBalanceLine _homeBalanceLine = HomeBalanceLine.allTime;

  /// Что показывать строкой «Баланс» на «Главной».
  HomeBalanceLine get homeBalanceLine => _homeBalanceLine;

  /// Меняет строку «Баланс» сразу, запись в базу идёт в фоне; ошибка записи
  /// не откатывает выбор, а только попадает в лог (как у темы).
  void setHomeBalanceLine(HomeBalanceLine value) {
    if (value == _homeBalanceLine) return;
    _homeBalanceLine = value;
    notifyListeners();
    unawaited(_persistHomeBalanceLine(value));
  }

  Future<void> _persistHomeBalanceLine(HomeBalanceLine value) async {
    final repository = _repository;
    if (repository == null) return;
    try {
      await repository.write(
        homeBalanceLineSettingKey,
        homeBalanceLineToStored(value),
      );
    } catch (error) {
      debugPrint('Не удалось сохранить строку «Баланс»: $error');
    }
  }

  /// Основная валюта (по умолчанию рубль).
  CurrencyInfo get mainCurrency => _mainCurrency;

  /// Код основной валюты.
  String get mainCurrencyCode => _mainCurrency.code;

  /// Меняет основную валюту после успешной записи в базу (без хранилища, как
  /// до [attach], - сразу). Возвращает `false`, если запись не удалась: тогда
  /// валюта остаётся прежней, а вызывающий скажет об этом пользователю. Не
  /// обычная валюта каталога превращается в рубль.
  Future<bool> setMainCurrency(CurrencyInfo value) async {
    final next = mainCurrencyFromStored(value.code);
    if (next.code == _mainCurrency.code) return true;
    final repository = _repository;
    if (repository != null) {
      try {
        await repository.write(
          mainCurrencySettingKey,
          mainCurrencyToStored(next),
        );
      } catch (error) {
        debugPrint('Не удалось сохранить основную валюту: $error');
        return false;
      }
    }
    _mainCurrency = next;
    notifyListeners();
    return true;
  }

  /// Id основного счёта, как он записан (счёта может уже не быть, он может
  /// быть в архиве или в другой валюте: годен ли он, решает вызывающий).
  String? get defaultAccountId => _defaultAccountId;

  /// Запоминает основной счёт после успешной записи; `false` - запись не
  /// удалась, значение прежнее.
  Future<bool> setDefaultAccountId(String id) async {
    if (id.isEmpty) return false;
    if (id == _defaultAccountId) return true;
    final repository = _repository;
    if (repository != null) {
      try {
        await repository.write(defaultAccountSettingKey, id);
      } catch (error) {
        debugPrint('Не удалось сохранить основной счёт: $error');
        return false;
      }
    }
    _defaultAccountId = id;
    notifyListeners();
    return true;
  }

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
      final stored = await repository.read(homeBalanceLineSettingKey);
      if (_repository != repository) return;
      final line = homeBalanceLineFromStored(stored);
      if (line != _homeBalanceLine) {
        _homeBalanceLine = line;
        notifyListeners();
      }
    } catch (error) {
      debugPrint('Не удалось прочитать строку «Баланс» из настроек: $error');
    }
    try {
      final stored = await repository.read(mainCurrencySettingKey);
      if (_repository != repository) return;
      final currency = mainCurrencyFromStored(stored);
      if (currency.code != _mainCurrency.code) {
        _mainCurrency = currency;
        notifyListeners();
      }
    } catch (error) {
      debugPrint('Не удалось прочитать основную валюту из настроек: $error');
    }
    try {
      final stored = await repository.read(defaultAccountSettingKey);
      if (_repository != repository) return;
      final id = (stored == null || stored.isEmpty) ? null : stored;
      if (id != _defaultAccountId) {
        _defaultAccountId = id;
        notifyListeners();
      }
    } catch (error) {
      debugPrint('Не удалось прочитать основной счёт из настроек: $error');
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
