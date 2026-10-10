import 'package:money_app/app/drift_data_eraser.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/core/ui/category_icons.dart';
import 'package:money_app/features/accounts/data/accounts_repository_impl.dart';
import 'package:money_app/features/accounts/data/transfers_repository_impl.dart';
import 'package:money_app/features/accounts/domain/accounts_repository.dart';
import 'package:money_app/features/accounts/domain/transfers_repository.dart';
import 'package:money_app/features/categories/data/categories_repository_impl.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/csv_import/data/csv_import_writer.dart';
import 'package:money_app/features/csv_import/domain/csv_import_store.dart';
import 'package:money_app/features/recurring/data/recurring_repository_impl.dart';
import 'package:money_app/features/recurring/domain/recurring_repository.dart';
import 'package:money_app/features/settings/domain/data_eraser.dart';
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
    required this.accounts,
    required this.transfers,
    required this.recurring,
    required this.settings,
    required this.clock,
    required this.idGenerator,
    required this.csvImport,
    required this.dataEraser,
  });

  /// Собирает боевой набор поверх открытой базы [database].
  ///
  /// Оба репозитория и генератор id получают тот же [clock]. Если
  /// [idGenerator] не задан, берётся [UuidV7Generator]. Импорт CSV пишет
  /// через те же репозитории и ту же базу: так его транзакция общая.
  factory AppServices.forDatabase(
    AppDatabase database, {
    required AppSettingsController settings,
    Clock clock = const SystemClock(),
    IdGenerator? idGenerator,
  }) {
    final categories = DriftCategoriesRepository(database, clock: clock);
    final transactions = DriftTransactionsRepository(database, clock: clock);
    final accounts = DriftAccountsRepository(database, clock: clock);
    final transfers = DriftTransfersRepository(database, clock: clock);
    final recurring = DriftRecurringRepository(
      database,
      transactions,
      clock: clock,
    );
    final ids = idGenerator ?? UuidV7Generator(clock: clock);
    return AppServices(
      categories: categories,
      transactions: transactions,
      accounts: accounts,
      transfers: transfers,
      recurring: recurring,
      settings: settings,
      clock: clock,
      idGenerator: ids,
      csvImport: CsvImportWriter(
        db: database,
        categories: categories,
        accounts: accounts,
        transfers: transfers,
        transactions: transactions,
        recurring: recurring,
        clock: clock,
        ids: ids,
        isKnownIconKey: isKnownCategoryIconKey,
      ),
      dataEraser: DriftDataEraser(database, idGenerator: ids, clock: clock),
    );
  }

  final CategoriesRepository categories;
  final TransactionsRepository transactions;
  final AccountsRepository accounts;
  final TransfersRepository transfers;
  final RecurringRepository recurring;
  final AppSettingsController settings;
  final Clock clock;
  final IdGenerator idGenerator;

  /// Подготовка и запись импорта CSV.
  final CsvImportStore csvImport;

  /// Стирание всех данных пользователя («Очистить всё»).
  final DataEraser dataEraser;
}
