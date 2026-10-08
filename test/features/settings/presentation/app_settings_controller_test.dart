import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/time/date_only.dart';
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
  test('основная валюта: по умолчанию RUB, USD пишется и читается', () async {
    final repo = _FakeSettingsRepository();
    final controller = AppSettingsController();
    addTearDown(controller.dispose);
    await controller.attach(repo);
    expect(controller.mainCurrency.code, 'RUB');

    expect(await controller.setMainCurrency(catalogCurrency('USD')!), isTrue);
    expect(controller.mainCurrencyCode, 'USD');
    expect(repo.data[mainCurrencySettingKey], 'USD');

    final second = AppSettingsController();
    addTearDown(second.dispose);
    await second.attach(repo);
    expect(second.mainCurrency.code, 'USD');
  });

  test(
    'основная валюта: сбой записи - валюта прежняя, результат false',
    () async {
      final repo = _FakeSettingsRepository(failWrite: true);
      final controller = AppSettingsController();
      addTearDown(controller.dispose);
      await controller.attach(repo);
      var notified = 0;
      controller.addListener(() => notified++);

      expect(
        await controller.setMainCurrency(catalogCurrency('USD')!),
        isFalse,
      );
      expect(controller.mainCurrencyCode, 'RUB');
      expect(notified, 0);

      repo.failWrite = false;
      expect(await controller.setMainCurrency(catalogCurrency('USD')!), isTrue);
      expect(controller.mainCurrencyCode, 'USD');
      expect(notified, 1);
    },
  );

  test(
    'основная валюта: сбой чтения - остаётся RUB, attach не падает',
    () async {
      final repo = _FakeSettingsRepository(failRead: true);
      final controller = AppSettingsController();
      addTearDown(controller.dispose);
      await controller.attach(repo);
      expect(controller.mainCurrencyCode, 'RUB');
    },
  );

  test('основная валюта: испорченное значение даёт RUB', () {
    for (final bad in ['usd', 'USDT', 'BTC', 'XYZ', '', null]) {
      expect(mainCurrencyFromStored(bad).code, 'RUB', reason: '$bad');
    }
    expect(mainCurrencyFromStored('USD').code, 'USD');
  });

  test(
    'основная валюта: испорченное значение в базе не ломает attach',
    () async {
      final repo = _FakeSettingsRepository()
        ..data[mainCurrencySettingKey] = 'BTC';
      final controller = AppSettingsController();
      addTearDown(controller.dispose);
      await controller.attach(repo);
      expect(controller.mainCurrency.code, 'RUB');
    },
  );

  group('основной счёт', () {
    test('по умолчанию нет; запись и чтение; уведомление', () async {
      final repo = _FakeSettingsRepository();
      final controller = AppSettingsController();
      addTearDown(controller.dispose);
      await controller.attach(repo);
      expect(controller.defaultAccountId, isNull);
      var notified = 0;
      controller.addListener(() => notified++);

      expect(await controller.setDefaultAccountId('acc-1'), isTrue);
      expect(controller.defaultAccountId, 'acc-1');
      expect(repo.data[defaultAccountSettingKey], 'acc-1');
      expect(notified, 1);
      // То же значение: без записи и уведомления.
      expect(await controller.setDefaultAccountId('acc-1'), isTrue);
      expect(repo.writes, 1);
      expect(notified, 1);

      final second = AppSettingsController();
      addTearDown(second.dispose);
      await second.attach(repo);
      expect(second.defaultAccountId, 'acc-1');
    });

    test('сбой записи: значение прежнее, результат false', () async {
      final repo = _FakeSettingsRepository(failWrite: true);
      final controller = AppSettingsController();
      addTearDown(controller.dispose);
      await controller.attach(repo);
      expect(await controller.setDefaultAccountId('acc-1'), isFalse);
      expect(controller.defaultAccountId, isNull);
    });

    test('пустое и испорченное значение в базе - основного нет', () async {
      for (final bad in ['', null]) {
        final repo = _FakeSettingsRepository();
        if (bad != null) repo.data[defaultAccountSettingKey] = bad;
        final controller = AppSettingsController();
        addTearDown(controller.dispose);
        await controller.attach(repo);
        expect(controller.defaultAccountId, isNull, reason: '$bad');
      }
      final controller = AppSettingsController();
      addTearDown(controller.dispose);
      await controller.attach(_FakeSettingsRepository(failRead: true));
      expect(controller.defaultAccountId, isNull);
      expect(await controller.setDefaultAccountId(''), isFalse);
    });
  });

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

  group('день последней выгрузки', () {
    test('по умолчанию null', () {
      final controller = AppSettingsController();
      addTearDown(controller.dispose);

      expect(controller.lastExportDay, isNull);
    });

    test('attach читает сохранённый день и уведомляет', () async {
      final repo = _FakeSettingsRepository()
        ..data[lastExportDaySettingKey] = '20261007';
      final controller = AppSettingsController();
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.attach(repo);

      expect(controller.lastExportDay, DateOnly(2026, 10, 7));
      expect(notifications, 1);
      expect(repo.writes, 0);
    });

    test('испорченное значение даёт null', () async {
      for (final bad in ['', 'abc', '20261340', '20260230', '0', '-5']) {
        final repo = _FakeSettingsRepository()
          ..data[lastExportDaySettingKey] = bad;
        final controller = AppSettingsController();
        addTearDown(controller.dispose);

        await controller.attach(repo);

        expect(controller.lastExportDay, isNull, reason: bad);
      }
    });

    test('setLastExportDay обновляет, уведомляет и пишет', () async {
      final repo = _FakeSettingsRepository();
      final controller = AppSettingsController();
      addTearDown(controller.dispose);
      await controller.attach(repo);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setLastExportDay(DateOnly(2026, 10, 7));
      await Future<void>.delayed(Duration.zero);

      expect(controller.lastExportDay, DateOnly(2026, 10, 7));
      expect(notifications, 1);
      expect(repo.data[lastExportDaySettingKey], '20261007');
    });

    test('повтор того же дня: без уведомления и второй записи', () async {
      final repo = _FakeSettingsRepository();
      final controller = AppSettingsController();
      addTearDown(controller.dispose);
      await controller.attach(repo);
      controller.setLastExportDay(DateOnly(2026, 10, 7));
      await Future<void>.delayed(Duration.zero);
      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.setLastExportDay(DateOnly(2026, 10, 7));
      await Future<void>.delayed(Duration.zero);

      expect(notifications, 0);
      expect(repo.writes, 1);
    });

    test('attach без сохранённого дня: без уведомления и записи', () async {
      final repo = _FakeSettingsRepository();
      final controller = AppSettingsController();
      addTearDown(controller.dispose);
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.attach(repo);

      expect(notifications, 0);
      expect(repo.writes, 0);
    });

    test('ошибка записи не откатывает день и не падает', () async {
      final repo = _FakeSettingsRepository(failWrite: true);
      final controller = AppSettingsController();
      addTearDown(controller.dispose);
      await controller.attach(repo);

      final errors = <Object>[];
      await runZonedGuarded(() async {
        controller.setLastExportDay(DateOnly(2026, 10, 7));
        await Future<void>.delayed(Duration.zero);
      }, (error, _) => errors.add(error));

      expect(repo.writes, 1);
      expect(controller.lastExportDay, DateOnly(2026, 10, 7));
      expect(errors, isEmpty);
    });

    test('ошибка чтения: день остаётся null', () async {
      final controller = AppSettingsController();
      addTearDown(controller.dispose);

      await controller.attach(_FakeSettingsRepository(failRead: true));

      expect(controller.lastExportDay, isNull);
    });
  });
}
