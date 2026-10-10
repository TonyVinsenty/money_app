import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../generated_migrations/schema.dart';

/// Схема v2 выпущена и неизменна. Приложение теперь на v3, поэтому «свежая
/// база = снимок» проверяется в `schema_v3_test.dart`, а здесь - что снимок v2
/// остался прежним (он нужен тесту миграции v2 -> v3).
void main() {
  test('the version 2 snapshot still describes the released schema', () async {
    final verifier = SchemaVerifier(GeneratedHelper());
    final schema = await verifier.schemaAt(2);

    final names = schema.rawDatabase
        .select(
          "SELECT name FROM sqlite_master WHERE type IN ('table', 'index') "
          "AND sql IS NOT NULL AND name NOT LIKE 'sqlite_%'",
        )
        .map((r) => r['name'] as String);
    expect(
      names,
      unorderedEquals([
        'app_settings',
        'categories',
        'categories_kind_level_order',
        'categories_level_order',
        'transactions',
        'transactions_category_occurred_on',
        'transactions_occurred_on_at',
        'transactions_account',
        'accounts',
        'accounts_order',
        'transfers',
        'transfers_occurred_on_at',
        'transfers_from_account',
        'transfers_to_account',
      ]),
    );
    final columns = schema.rawDatabase
        .select('PRAGMA table_info(transactions)')
        .map((r) => r['name'] as String);
    expect(columns, contains('account_id'));
    expect(schema.rawDatabase.select('PRAGMA user_version').first.values, [2]);
  });
}
