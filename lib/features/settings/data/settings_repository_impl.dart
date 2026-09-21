import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/features/settings/domain/settings_repository.dart';

/// Реализация [SettingsRepository] на drift: таблица `app_settings`.
class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository(this._db, {this._clock = const SystemClock()});

  final AppDatabase _db;
  final Clock _clock;

  @override
  Future<String?> read(String key) async {
    final row = await (_db.select(
      _db.appSettings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  @override
  Future<void> write(String key, String value) async {
    // Upsert: новая строка или перезапись существующей с тем же ключом.
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: key,
            value: value,
            updatedAt: _clock.now().toUtc().millisecondsSinceEpoch,
          ),
        );
  }
}
