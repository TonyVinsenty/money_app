import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/database/app_database.dart';

void main() {
  group('AppDatabase', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('schemaVersion is 3', () {
      expect(db.schemaVersion, 3);
    });

    test('writes a setting and reads it back', () async {
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: 'theme_mode',
              value: 'dark',
              updatedAt: 1700000000000,
            ),
          );

      final rows = await db.select(db.appSettings).get();

      expect(rows, hasLength(1));
      expect(rows.single.key, 'theme_mode');
      expect(rows.single.value, 'dark');
      expect(rows.single.updatedAt, 1700000000000);
    });

    test(
      'insertOnConflictUpdate updates the row instead of adding one',
      () async {
        await db
            .into(db.appSettings)
            .insert(
              AppSettingsCompanion.insert(
                key: 'theme_mode',
                value: 'dark',
                updatedAt: 1,
              ),
            );

        await db
            .into(db.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion.insert(
                key: 'theme_mode',
                value: 'light',
                updatedAt: 2,
              ),
            );

        final rows = await db.select(db.appSettings).get();

        expect(rows, hasLength(1));
        expect(rows.single.value, 'light');
        expect(rows.single.updatedAt, 2);
      },
    );

    test('foreign keys are enabled after opening', () async {
      final rows = await db.customSelect('PRAGMA foreign_keys').get();

      expect(rows.single.read<int>('foreign_keys'), 1);
    });

    test(
      'app_settings columns: key is primary key, updated_at is INTEGER',
      () async {
        final rows = await db
            .customSelect('PRAGMA table_info(app_settings)')
            .get();
        final byName = {for (final r in rows) r.read<String>('name'): r};

        expect(byName.keys, containsAll(['key', 'value', 'updated_at']));
        expect(byName['key']!.read<int>('pk'), 1);
        expect(byName['key']!.read<String>('type'), 'TEXT');
        expect(byName['value']!.read<String>('type'), 'TEXT');
        expect(byName['value']!.read<int>('notnull'), 1);
        expect(byName['updated_at']!.read<String>('type'), 'INTEGER');
        expect(byName['updated_at']!.read<int>('notnull'), 1);
      },
    );
  });
}
