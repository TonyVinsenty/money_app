import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/features/categories/data/categories_repository_impl.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/categories/domain/default_categories.dart';

/// Засевает категории по умолчанию при первом запуске.
///
/// [seed] идемпотентен: если в таблице есть хоть одна строка (в том числе
/// архивная или мягко удалённая), он ничего не делает. Поэтому пользователь,
/// который переименовал, заархивировал или переставил категории, при
/// следующем запуске не получит исходный набор обратно.
///
/// Проверка и вставка идут в ОДНОЙ транзакции базы: либо создаются все
/// категории набора, либо (при любой ошибке) ни одной.
class DefaultCategoriesSeeder {
  DefaultCategoriesSeeder(
    this._db, {
    this._idGenerator = const UuidV7Generator(),
    this._clock = const SystemClock(),
  });

  final AppDatabase _db;
  final IdGenerator _idGenerator;
  final Clock _clock;

  Future<void> seed() {
    // Вызовы репозитория внутри колбэка присоединяются к этой транзакции,
    // потому что репозиторий работает с той же базой.
    return _db.transaction(() async {
      final repository = DriftCategoriesRepository(_db, clock: _clock);
      if (await repository.hasAny()) {
        return;
      }
      // Порядок считаем отдельно для каждого вида: 0, 1, 2...
      final nextSortOrder = {for (final kind in CategoryKind.values) kind: 0};
      for (final template in defaultCategories) {
        final sortOrder = nextSortOrder[template.kind]!;
        nextSortOrder[template.kind] = sortOrder + 1;
        await repository.create(
          Category.topLevel(
            id: _idGenerator.newId(),
            kind: template.kind,
            name: template.name,
            iconKey: template.iconKey,
            sortOrder: sortOrder,
          ),
        );
      }
    });
  }
}
