import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app_services.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/domain/transactions_repository.dart';

import 'fake_id_generator.dart';
import 'fixed_clock.dart';

/// Пустой фейк репозитория категорий: методы не реализованы, любой вызов
/// бросит ошибку. Годится, когда тесту нужен лишь сам объект («тот же ли он»).
class FakeCategoriesRepository extends Fake implements CategoriesRepository {}

/// Фейк репозитория категорий, у которого работает только `watchTopLevel`:
/// отдаёт то, что тест кладёт в [source], оставляя, как и настоящий репозиторий,
/// только живые категории верхнего уровня нужного вида. Остальные методы
/// бросают ошибку.
class StreamCategoriesRepository extends FakeCategoriesRepository {
  StreamCategoriesRepository(this.source);

  /// Всё, что «лежит в базе»: тест сам решает, когда и что отдать.
  final Stream<List<Category>> source;

  @override
  Stream<List<Category>> watchTopLevel(CategoryKind kind) {
    return source.map(
      (all) => [
        for (final c in all)
          if (c.kind == kind && c.isTopLevel && !c.isArchived) c,
      ],
    );
  }
}

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
