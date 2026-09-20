import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:money_app/core/database/app_database.dart';

/// Открывает базу в оперативной памяти: быстро, без файлов, каждый вызов —
/// новая пустая база. Подходит как `openDatabase` для `MoneyApp` в тестах.
///
/// Соединение с `closeStreamsSynchronously: true` — так по документации drift
/// поступают в виджет-тестах, чтобы не оставались «висящие» таймеры (ADR 0001).
Future<AppDatabase> openInMemoryDatabase() async {
  return AppDatabase(
    DatabaseConnection(
      NativeDatabase.memory(),
      closeStreamsSynchronously: true,
    ),
  );
}
