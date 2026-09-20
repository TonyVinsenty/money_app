import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/features/categories/data/default_categories_seeder.dart';

/// Открывает базу функцией [open] и засевает категории по умолчанию.
///
/// Засев идемпотентен (см. `DefaultCategoriesSeeder`): на непустой таблице
/// ничего не происходит. Если засев упал, базу закрываем (иначе останется
/// «висеть» открытое соединение) и пробрасываем исходную ошибку: её увидит
/// экран «Не удалось открыть базу данных» с кнопкой «Повторить». Ошибка самого
/// закрытия исходную не затирает.
///
/// [idGenerator] и [clock] нужны тестам; в приложении берутся настоящие.
Future<AppDatabase> openAndSeedDatabase(
  Future<AppDatabase> Function() open, {
  IdGenerator? idGenerator,
  Clock? clock,
}) async {
  final database = await open();
  final effectiveClock = clock ?? const SystemClock();
  try {
    await DefaultCategoriesSeeder(
      database,
      idGenerator: idGenerator ?? UuidV7Generator(clock: effectiveClock),
      clock: effectiveClock,
    ).seed();
  } catch (_) {
    try {
      await database.close();
    } catch (_) {}
    rethrow;
  }
  return database;
}
