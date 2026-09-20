import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  // Дым-тест: проверяем только то, что нативный SQLite вообще загружается
  // и работает в `flutter test`. Код приложения здесь не участвует.
  group('sqlite3 smoke', () {
    late Database db;

    setUp(() {
      db = sqlite3.openInMemory();
    });

    tearDown(() {
      db.close();
    });

    test(
      'creates a table, inserts a row with a parameter and reads it back',
      () {
        db.execute(
          'CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
        );

        final insert = db.prepare('INSERT INTO t (id, name) VALUES (?, ?)');
        insert.execute([1, 'Coffee']);
        insert.close();

        final rows = db.select('SELECT id, name FROM t WHERE id = ?', [1]);

        expect(rows, hasLength(1));
        expect(rows.single['id'], 1);
        expect(rows.single['name'], 'Coffee');
      },
    );

    test('enables foreign keys via PRAGMA', () {
      db.execute('PRAGMA foreign_keys = ON');

      final rows = db.select('PRAGMA foreign_keys');

      expect(rows.single['foreign_keys'], 1);
    });
  });
}
