import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/features/categories/data/default_categories_seeder.dart';
import 'package:money_app/features/settings/domain/data_eraser.dart';

/// Стирает данные пользователя в базе drift одной транзакцией.
///
/// Удаление настоящее (не мягкое), в порядке внешних ключей: записи «к оплате»,
/// регулярные платежи, переводы,
/// операции, счета, подкатегории, категории. Затем в той же транзакции
/// засеваем стандартные категории: таблица пуста, поэтому засев сработает.
/// Таблицу `app_settings` не трогаем: тема, валюта и прочее остаются.
/// Если засев упал, откатывается всё, включая удаления.
class DriftDataEraser implements DataEraser {
  DriftDataEraser(
    this._db, {
    this._idGenerator = const UuidV7Generator(),
    this._clock = const SystemClock(),
  });

  final AppDatabase _db;
  final IdGenerator _idGenerator;
  final Clock _clock;

  @override
  Future<void> eraseAll() {
    return _db.transaction(() async {
      await _db.delete(_db.recurringDues).go();
      await _db.delete(_db.recurringPayments).go();
      await _db.delete(_db.transfers).go();
      await _db.delete(_db.transactions).go();
      await _db.delete(_db.accounts).go();
      await (_db.delete(
        _db.categories,
      )..where((c) => c.parentId.isNotNull())).go();
      await _db.delete(_db.categories).go();
      await DefaultCategoriesSeeder(
        _db,
        idGenerator: _idGenerator,
        clock: _clock,
      ).seed();
    });
  }
}
