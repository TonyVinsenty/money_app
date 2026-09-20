import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/database/app_database.dart';

/// Белый список: единственные типы колонок, разрешённые в базе. Всё остальное
/// (REAL, FLOAT, NUMERIC, DECIMAL, MONEY, BLOB, INT, BOOLEAN и даже колонка
/// без типа) — нарушение. Так дробное число не проскочит под незнакомым
/// названием типа (ADR 0001/0004: деньги — только целые минорные единицы).
const _allowedTypes = {'TEXT', 'INTEGER'};

/// Возвращает сообщения обо всех колонках, чей тип не из белого списка, во
/// всех таблицах базы (служебные таблицы `sqlite_*` пропускаются). Пустой
/// список — всё чисто. Сравнение без учёта регистра, пробелы по краям
/// игнорируются.
Future<List<String>> findDisallowedColumnTypes(GeneratedDatabase db) async {
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
      if (!_allowedTypes.contains(type.trim().toUpperCase())) {
        problems.add(
          '$tableName.${column.read<String>('name')} имеет тип $type — '
          'разрешены только TEXT и INTEGER (ADR 0001/0004)',
        );
      }
    }
  }
  return problems;
}

void main() {
  group('schema column types whitelist', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('every column of the app database is TEXT or INTEGER', () async {
      final problems = await findDisallowedColumnTypes(db);

      expect(problems, isEmpty, reason: problems.join('\n'));
    });

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

    test('the check catches disallowed types in a sample table', () async {
      // Колонка price объявлена без типа вообще: SQLite отдаёт пустой тип.
      await db.customStatement(
        'CREATE TABLE bad_sample ('
        'id INTEGER, price, amount MONEY, r REAL, score float, '
        'ratio DOUBLE PRECISION, total NUMERIC(10, 2), small INT, '
        'ok TEXT)',
      );

      final problems = await findDisallowedColumnTypes(db);

      const tail = '— разрешены только TEXT и INTEGER (ADR 0001/0004)';
      expect(problems, [
        'bad_sample.price имеет тип  $tail',
        'bad_sample.amount имеет тип MONEY $tail',
        'bad_sample.r имеет тип REAL $tail',
        'bad_sample.score имеет тип float $tail',
        'bad_sample.ratio имеет тип DOUBLE PRECISION $tail',
        'bad_sample.total имеет тип NUMERIC(10, 2) $tail',
        'bad_sample.small имеет тип INT $tail',
      ]);
    });

    test('a table of only TEXT and INTEGER columns passes', () async {
      await db.customStatement(
        'CREATE TABLE good_sample (id TEXT, n integer, note Text)',
      );

      final problems = await findDisallowedColumnTypes(db);

      expect(problems, isEmpty, reason: problems.join('\n'));
    });
  });
}
