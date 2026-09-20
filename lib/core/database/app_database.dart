import 'package:drift/drift.dart';
import 'package:money_app/core/database/tables/app_settings.dart';

part 'app_database.g.dart';

/// База данных приложения (ADR 0001).
///
/// Исполнитель запросов ([QueryExecutor]) приходит параметром: в приложении
/// это будет файловая база, в тестах — `NativeDatabase.memory()`.
@DriftDatabase(tables: [AppSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    beforeOpen: (details) async {
      // SQLite по умолчанию не проверяет внешние ключи — включаем.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
