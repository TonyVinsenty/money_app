import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/features/categories/data/categories_repository_impl.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/transactions_repository.dart';

/// Набор общих зависимостей приложения: то, что экраны получают через
/// `AppScope.of(context)`.
///
/// Все поля — интерфейсы, а не конкретные классы: экран не знает, что внутри
/// drift, и в тестах сюда можно положить фейки. Саму базу данных наружу не
/// отдаём: экраны работают только через репозитории.
///
/// Набор неизменяемый. Объекты внутри создаются один раз (см. `AppScopeHost`):
/// потоки данных «держатся» на репозиториях, и пересоздавать их при каждой
/// перерисовке нельзя.
final class AppServices {
  const AppServices({
    required this.categories,
    required this.transactions,
    required this.settings,
    required this.clock,
    required this.idGenerator,
  });

  /// Собирает боевой набор поверх открытой базы [database].
  ///
  /// Оба репозитория и генератор id получают тот же [clock]. Если
  /// [idGenerator] не задан, берётся [UuidV7Generator].
  factory AppServices.forDatabase(
    AppDatabase database, {
    required AppSettingsController settings,
    Clock clock = const SystemClock(),
    IdGenerator? idGenerator,
  }) {
    return AppServices(
      categories: DriftCategoriesRepository(database, clock: clock),
      transactions: DriftTransactionsRepository(database, clock: clock),
      settings: settings,
      clock: clock,
      idGenerator: idGenerator ?? UuidV7Generator(clock: clock),
    );
  }

  final CategoriesRepository categories;
  final TransactionsRepository transactions;
  final AppSettingsController settings;
  final Clock clock;
  final IdGenerator idGenerator;
}
