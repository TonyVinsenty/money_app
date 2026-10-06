import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/features/settings/data/settings_repository_impl.dart';
import 'package:money_app/features/settings/domain/settings_repository.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

import '../../../support/fixed_clock.dart';

void main() {
  group('DriftSettingsRepository', () {
    late AppDatabase db;
    late FixedClock clock;
    late DriftSettingsRepository repo;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      clock = FixedClock(DateTime.utc(2026, 9, 21, 12));
      repo = DriftSettingsRepository(db, clock: clock);
    });

    tearDown(() => db.close());

    Future<AppSetting> row(String key) => (db.select(
      db.appSettings,
    )..where((s) => s.key.equals(key))).getSingle();

    test('пустая база: настройки нет', () async {
      expect(await repo.read(themeModeSettingKey), isNull);
    });

    test('записанное значение читается, updated_at — момент записи', () async {
      await repo.write(themeModeSettingKey, 'dark');

      expect(await repo.read(themeModeSettingKey), 'dark');
      expect(
        (await row(themeModeSettingKey)).updatedAt,
        clock.value.millisecondsSinceEpoch,
      );
    });

    test('перезапись меняет значение и updated_at, строка одна', () async {
      await repo.write(themeModeSettingKey, 'dark');
      clock.advance(const Duration(minutes: 5));
      await repo.write(themeModeSettingKey, 'light');

      expect(await repo.read(themeModeSettingKey), 'light');
      final rows = await db.select(db.appSettings).get();
      expect(rows, hasLength(1));
      expect(rows.single.updatedAt, clock.value.millisecondsSinceEpoch);
    });

    test('разные ключи не мешают друг другу', () async {
      await repo.write(themeModeSettingKey, 'dark');
      await repo.write('other', 'x');

      expect(await repo.read(themeModeSettingKey), 'dark');
      expect(await repo.read('other'), 'x');
    });

    test('день последней выгрузки: запись, чтение, перезапись', () async {
      expect(await repo.read(lastExportDaySettingKey), isNull);

      await repo.write(lastExportDaySettingKey, '20261007');
      expect(await repo.read(lastExportDaySettingKey), '20261007');

      await repo.write(lastExportDaySettingKey, '20261008');
      expect(await repo.read(lastExportDaySettingKey), '20261008');
    });

    test('мусор в базе: контроллер применяет «как в системе»', () async {
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion(
              key: const Value(themeModeSettingKey),
              value: const Value('purple'),
              updatedAt: const Value(1),
            ),
          );
      final controller = AppSettingsController();
      addTearDown(controller.dispose);

      await controller.attach(repo);

      expect(controller.themeMode, ThemeMode.system);
    });

    test('пустая база: контроллер применяет «как в системе»', () async {
      final controller = AppSettingsController();
      addTearDown(controller.dispose);

      await controller.attach(repo);

      expect(controller.themeMode, ThemeMode.system);
    });
  });
}
