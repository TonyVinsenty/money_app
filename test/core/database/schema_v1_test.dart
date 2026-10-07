import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

// Относительный импорт: сгенерированный помощник лежит в test/, а не в lib/,
// поэтому package:-путь к нему невозможен.
import '../../generated_migrations/schema.dart';

/// Схема v1 выпущена и неизменна. Приложение теперь на v2, поэтому «свежая
/// база = снимок» проверяется в `schema_v2_test.dart`, а здесь — что снимок v1
/// остался прежним (он нужен тесту миграции v1 -> v2).
void main() {
  test('the version 1 snapshot still describes the released schema', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(1);

    final names = schema.rawDatabase
        .select(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name NOT LIKE 'sqlite_%'",
        )
        .map((r) => r['name'] as String)
        .toSet();
    expect(names, {'app_settings', 'categories', 'transactions'});

    final columns = schema.rawDatabase
        .select('PRAGMA table_info(transactions)')
        .map((r) => r['name'] as String);
    expect(columns, isNot(contains('account_id')));
    expect(columns, hasLength(12));
  });
}
