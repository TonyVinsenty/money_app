import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// Минимальная «база» без таблиц и без кодогенерации: только чтобы получить
// доступ к customSelect/customStatement. Будущий AppDatabase устроен так же:
// принимает QueryExecutor в конструкторе (ADR 0001).
class _SmokeDatabase extends GeneratedDatabase {
  _SmokeDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];
}

void main() {
  // Дым-тест: проверяем только то, что drift открывает NativeDatabase.memory()
  // и выполняет обычный SQL. Код приложения здесь не участвует.
  group('drift smoke', () {
    late _SmokeDatabase db;

    setUp(() {
      db = _SmokeDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('runs SELECT 1', () async {
      final rows = await db.customSelect('SELECT 1 AS v').get();

      expect(rows, hasLength(1));
      expect(rows.single.read<int>('v'), 1);
    });

    test('runs a query with a bound parameter', () async {
      final rows = await db
          .customSelect('SELECT ? + 1 AS v', variables: [Variable.withInt(41)])
          .get();

      expect(rows.single.read<int>('v'), 42);
    });

    test('creates a table, inserts a row and reads it back', () async {
      await db.customStatement(
        'CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT NOT NULL)',
      );
      await db.customStatement('INSERT INTO t (id, name) VALUES (?, ?)', [
        1,
        'Coffee',
      ]);

      final rows = await db
          .customSelect(
            'SELECT id, name FROM t WHERE id = ?',
            variables: [Variable.withInt(1)],
          )
          .get();

      expect(rows, hasLength(1));
      expect(rows.single.read<int>('id'), 1);
      expect(rows.single.read<String>('name'), 'Coffee');
    });
  });
}
