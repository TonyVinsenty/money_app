import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/database/app_database.dart';

/// Типы колонок, в которых живут дробные числа. Деньги в них хранить нельзя
/// (ADR 0001/0004): только целые минорные единицы.
const _forbiddenTypeParts = ['REAL', 'FLOAT', 'DOUBLE', 'NUMERIC', 'DECIMAL'];

/// Возвращает сообщения обо всех колонках с дробным типом во всех таблицах
/// базы (служебные таблицы `sqlite_*` пропускаются). Пустой список — всё чисто.
Future<List<String>> findFractionalColumns(GeneratedDatabase db) async {
  final tables = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .get();

  final problems = <String>[];
  for (final table in tables) {
    final tableName = table.read<String>('name');
    final columns = await db
        .customSelect(
          'SELECT name, type FROM pragma_table_info(?)',
          variables: [Variable<String>(tableName)],
        )
        .get();
    for (final column in columns) {
      final type = column.read<String>('type');
      final upper = type.toUpperCase();
      if (_forbiddenTypeParts.any(upper.contains)) {
        problems.add(
          '$tableName.${column.read<String>('name')} имеет тип $type — '
          'дробные типы запрещены (ADR 0001/0004)',
        );
      }
    }
  }
  return problems;
}

void main() {
  group('schema has no fractional columns', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test(
      'no table of the app database has REAL/FLOAT/DOUBLE/NUMERIC',
      () async {
        final problems = await findFractionalColumns(db);

        expect(problems, isEmpty, reason: problems.join('\n'));
      },
    );

    test('the guard really looks at the app tables', () async {
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name NOT LIKE 'sqlite_%'",
          )
          .get();

      expect(
        tables.map((r) => r.read<String>('name')),
        containsAll(['app_settings', 'categories', 'transactions']),
      );
    });

    test('the check catches fractional columns in a sample table', () async {
      await db.customStatement(
        'CREATE TABLE bad_sample ('
        'id INTEGER, price REAL, score float, ratio DOUBLE PRECISION, '
        'total NUMERIC(10, 2), ok TEXT)',
      );

      final problems = await findFractionalColumns(db);

      expect(problems, [
        'bad_sample.price имеет тип REAL — дробные типы запрещены (ADR 0001/0004)',
        'bad_sample.score имеет тип float — дробные типы запрещены (ADR 0001/0004)',
        'bad_sample.ratio имеет тип DOUBLE PRECISION — '
            'дробные типы запрещены (ADR 0001/0004)',
        'bad_sample.total имеет тип NUMERIC(10, 2) — '
            'дробные типы запрещены (ADR 0001/0004)',
      ]);
    });
  });
}
