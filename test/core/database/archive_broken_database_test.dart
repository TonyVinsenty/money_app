import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/open_and_seed_database.dart';
import 'package:money_app/core/database/archive_broken_database.dart';
import 'package:money_app/core/database/open_app_database.dart';

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('zuno_archive_test_');
  });

  tearDown(() {
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  });

  File file(String name) => File.fromUri(dir.uri.resolve(name));

  List<String> names() =>
      dir.listSync().map((e) => e.uri.pathSegments.last).toList()..sort();

  final now = DateTime(2026, 9, 20, 13, 5, 9);
  const stamped = 'zuno_broken_2026-09-20_130509';

  group('archiveDatabaseFileIn', () {
    test('keeps content byte for byte and removes the original name', () async {
      final bytes = List<int>.generate(300, (i) => i % 256);
      file(appDatabaseFileName).writeAsBytesSync(bytes);

      final result = await archiveDatabaseFileIn(dir, now: now);

      expect(result, isNotNull);
      expect(result!.uri.pathSegments.last, '$stamped.sqlite');
      expect(result.readAsBytesSync(), bytes);
      expect(file(appDatabaseFileName).existsSync(), isFalse);
      expect(names(), ['$stamped.sqlite']);
    });

    test('moves -wal, -shm and -journal companions together', () async {
      file(appDatabaseFileName).writeAsStringSync('main');
      file('$appDatabaseFileName-wal').writeAsStringSync('wal');
      file('$appDatabaseFileName-shm').writeAsStringSync('shm');
      file('$appDatabaseFileName-journal').writeAsStringSync('journal');

      await archiveDatabaseFileIn(dir, now: now);

      expect(names(), [
        '$stamped.sqlite',
        '$stamped.sqlite-journal',
        '$stamped.sqlite-shm',
        '$stamped.sqlite-wal',
      ]);
      expect(file('$stamped.sqlite-wal').readAsStringSync(), 'wal');
      expect(file('$stamped.sqlite-shm').readAsStringSync(), 'shm');
      expect(file('$stamped.sqlite-journal').readAsStringSync(), 'journal');
    });

    test('returns null and creates nothing when there is no file', () async {
      final result = await archiveDatabaseFileIn(dir, now: now);

      expect(result, isNull);
      expect(dir.listSync(), isEmpty);
    });

    test(
      'a taken name gets a _2 suffix and the other file is intact',
      () async {
        file(appDatabaseFileName).writeAsStringSync('new broken');
        file('$stamped.sqlite').writeAsStringSync('older archive');

        final result = await archiveDatabaseFileIn(dir, now: now);

        expect(result!.uri.pathSegments.last, '${stamped}_2.sqlite');
        expect(result.readAsStringSync(), 'new broken');
        expect(file('$stamped.sqlite').readAsStringSync(), 'older archive');
      },
    );

    test('names _2 and _3 are skipped when taken; then _4 is used', () async {
      file(appDatabaseFileName).writeAsStringSync('x');
      file('$stamped.sqlite').writeAsStringSync('a');
      file('${stamped}_2.sqlite').writeAsStringSync('b');
      file('${stamped}_3.sqlite').writeAsStringSync('c');

      final result = await archiveDatabaseFileIn(dir, now: now);

      expect(result!.uri.pathSegments.last, '${stamped}_4.sqlite');
    });

    test('a taken companion name alone also forces the suffix', () async {
      file(appDatabaseFileName).writeAsStringSync('main');
      file('$appDatabaseFileName-wal').writeAsStringSync('wal');
      // Занят только спутник: основного файла с таким именем нет.
      file('$stamped.sqlite-wal').writeAsStringSync('foreign wal');

      final result = await archiveDatabaseFileIn(dir, now: now);

      expect(result!.uri.pathSegments.last, '${stamped}_2.sqlite');
      expect(file('$stamped.sqlite-wal').readAsStringSync(), 'foreign wal');
      expect(file('${stamped}_2.sqlite-wal').readAsStringSync(), 'wal');
      expect(file('${stamped}_2.sqlite').readAsStringSync(), 'main');
    });

    test('failure on a companion rolls back and rethrows the original '
        'error', () async {
      file(appDatabaseFileName).writeAsStringSync('main');
      file('$appDatabaseFileName-wal').writeAsStringSync('wal');
      file('$appDatabaseFileName-shm').writeAsStringSync('shm');
      final failure = StateError('boom-on-shm');

      Future<void> rename(File source, String newPath) async {
        if (newPath.endsWith('-shm')) {
          throw failure;
        }
        await source.rename(newPath);
      }

      await expectLater(
        archiveDatabaseFileIn(dir, now: now, rename: rename),
        throwsA(same(failure)),
      );

      expect(names(), [
        appDatabaseFileName,
        '$appDatabaseFileName-shm',
        '$appDatabaseFileName-wal',
      ]);
      expect(file(appDatabaseFileName).readAsStringSync(), 'main');
      expect(file('$appDatabaseFileName-wal').readAsStringSync(), 'wal');
      expect(file('$appDatabaseFileName-shm').readAsStringSync(), 'shm');
    });

    test('failure on the main file changes nothing', () async {
      file(appDatabaseFileName).writeAsStringSync('main');
      file('$appDatabaseFileName-journal').writeAsStringSync('journal');
      final failure = StateError('boom-on-main');

      await expectLater(
        archiveDatabaseFileIn(
          dir,
          now: now,
          rename: (source, newPath) async => throw failure,
        ),
        throwsA(same(failure)),
      );

      expect(names(), [appDatabaseFileName, '$appDatabaseFileName-journal']);
      expect(file(appDatabaseFileName).readAsStringSync(), 'main');
      expect(
        file('$appDatabaseFileName-journal').readAsStringSync(),
        'journal',
      );
    });

    test('name format pads month, day, hour, minute and second', () async {
      file(appDatabaseFileName).writeAsStringSync('x');

      final result = await archiveDatabaseFileIn(
        dir,
        now: DateTime(2026, 1, 2, 3, 4, 5),
      );

      expect(
        result!.uri.pathSegments.last,
        'zuno_broken_2026-01-02_030405.sqlite',
      );
    });
  });

  test('a broken file is archived, then a fresh database opens with 14 '
      'categories', () async {
    final broken = file(appDatabaseFileName)..writeAsStringSync('это не база');
    final garbage = broken.readAsBytesSync();

    await expectLater(openAppDatabaseIn(dir), throwsA(anything));

    final archived = await archiveDatabaseFileIn(dir, now: now);
    expect(archived, isNotNull);

    final database = await openAndSeedDatabase(() => openAppDatabaseIn(dir));
    try {
      expect(await database.select(database.categories).get(), hasLength(14));
    } finally {
      await database.close();
    }

    expect(archived!.readAsBytesSync(), garbage);
    expect(archived.uri.pathSegments.last, '$stamped.sqlite');
  });
}
