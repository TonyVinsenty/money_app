import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app_services.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/domain/transactions_repository.dart';

import 'fake_id_generator.dart';
import 'fixed_clock.dart';

/// Пустой фейк репозитория категорий: методы не реализованы, любой вызов
/// бросит ошибку. Годится, когда тесту нужен лишь сам объект («тот же ли он»).
class FakeCategoriesRepository extends Fake implements CategoriesRepository {}

/// Пустой фейк репозитория операций (см. [FakeCategoriesRepository]).
class FakeTransactionsRepository extends Fake
    implements TransactionsRepository {}

/// Набор сервисов из фейков: то, что тест кладёт в `AppScope`.
///
/// [settings] передаёт сам тест: кто создал контроллер, тот и вызывает
/// `dispose`. Репозитории можно заменить своими, иначе подставляются пустые
/// фейки.
AppServices fakeAppServices({
  required AppSettingsController settings,
  CategoriesRepository? categories,
  TransactionsRepository? transactions,
}) {
  return AppServices(
    categories: categories ?? FakeCategoriesRepository(),
    transactions: transactions ?? FakeTransactionsRepository(),
    settings: settings,
    clock: FixedClock(DateTime.utc(2026, 9, 20, 12)),
    idGenerator: FakeIdGenerator(),
  );
}
