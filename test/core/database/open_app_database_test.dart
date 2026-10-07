import 'dart:io';

import 'package:drift/isolate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/database/open_app_database.dart';

void main() {
  group('openAppDatabaseIn', () {
    late Directory tempDir;
    // Базы, которые открыл тест: закрываем в tearDown, даже если тест упал.
    final opened = <AppDatabase>[];

    Future<AppDatabase> open(Directory directory) async {
      final db = await openAppDatabaseIn(directory);
      opened.add(db);
      return db;
    }

    Future<void> insertSetting(AppDatabase db, String key, String value) {
      return db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: key,
              value: value,
              updatedAt: 1700000000000,
            ),
          );
    }

    Future<int> readPragma(AppDatabase db, String name) async {
      final rows = await db.customSelect('PRAGMA $name').get();
      return rows.single.read<int>(name);
    }

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('zuno_db_test_');
    });

    tearDown(() async {
      // Каждую базу закрываем отдельно: одна ошибка не должна оставить
      // открытые файлы (и мусор в TEMP) от остальных.
      for (final db in opened) {
        try {
          await db.close();
        } catch (_) {}
      }
      opened.clear();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    File dbFile() => File.fromUri(tempDir.uri.resolve(appDatabaseFileName));

    test('creates the zuno.sqlite file right away', () async {
      expect(appDatabaseFileName, 'zuno.sqlite');
      expect(dbFile().existsSync(), isFalse);

      await open(tempDir);

      expect(dbFile().existsSync(), isTrue);
      expect(dbFile().lengthSync(), greaterThan(0));
    });

    test('creates the schema with all five tables', () async {
      final db = await open(tempDir);

      final rows = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      final names = rows.map((r) => r.read<String>('name')).toSet();

      expect(names, {
        'app_settings',
        'categories',
        'transactions',
        'accounts',
        'transfers',
      });
    });

    test('data survives closing and reopening the same file', () async {
      final first = await open(tempDir);
      await insertSetting(first, 'theme_mode', 'dark');
      await first.close();

      final second = await open(tempDir);
      final rows = await second.select(second.appSettings).get();

      expect(rows, hasLength(1));
      expect(rows.single.key, 'theme_mode');
      expect(rows.single.value, 'dark');
      expect(rows.single.updatedAt, 1700000000000);
    });

    test(
      'user_version is 2 and foreign keys are on, also after reopen',
      () async {
        final first = await open(tempDir);
        expect(await readPragma(first, 'user_version'), 2);
        expect(await readPragma(first, 'foreign_keys'), 1);
        await first.close();

        final second = await open(tempDir);
        expect(await readPragma(second, 'user_version'), 2);
        expect(await readPragma(second, 'foreign_keys'), 1);
      },
    );

    test('reopening does not recreate the schema or lose rows', () async {
      final first = await open(tempDir);
      await insertSetting(first, 'a', '1');
      await first.close();

      final second = await open(tempDir);
      await insertSetting(second, 'b', '2');
      final keys = (await second.select(second.appSettings).get())
          .map((r) => r.key)
          .toSet();

      expect(keys, {'a', 'b'});
    });

    test(
      'a file that is not a database gives an error and is released',
      () async {
        dbFile().writeAsStringSync('this is just plain text, not a database');

        await expectLater(
          openAppDatabaseIn(tempDir),
          // Запросы идут в отдельном потоке (isolate), поэтому ошибка SQLite
          // (код 26, «file is not a database») приходит обёрнутой в
          // DriftRemoteException.
          throwsA(
            isA<DriftRemoteException>().having(
              (e) => e.toString(),
              'message',
              contains('file is not a database'),
            ),
          ),
        );

        // Соединение закрыто: файл (и каталог) можно удалить, в том числе на
        // Windows, где открытый файл удалить нельзя.
        dbFile().deleteSync();
        expect(dbFile().existsSync(), isFalse);
      },
    );

    test(
      'a missing directory gives a clear error and creates nothing',
      () async {
        final missing = Directory.fromUri(tempDir.uri.resolve('no_such_dir/'));

        await expectLater(
          openAppDatabaseIn(missing),
          throwsA(
            isA<FileSystemException>().having(
              (e) => e.path,
              'path',
              missing.path,
            ),
          ),
        );

        expect(missing.existsSync(), isFalse);
        expect(tempDir.listSync(), isEmpty);
      },
    );
  });
}
