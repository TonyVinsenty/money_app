import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';

/// Платёж в списке вместе с ближайшей датой.
final class RecurringListItem {
  const RecurringListItem({required this.payment, required this.nextDue});

  final RecurringPayment payment;

  /// Ближайшая дата платежа не раньше «сегодня»; `null`, если платёж закончился.
  final DateOnly? nextDue;
}

/// Хранилище регулярных платежей (ADR 0011).
///
/// Общие ошибки методов:
/// - `RecurringRuleException` - нарушено правило платежа (в том числе связи с
///   категорией и счётом: вид, уровень, архив, валюта);
/// - `DataCorruptedException` - строка в хранилище испорчена;
/// - `ArgumentError` - платежа, категории или счёта с таким id нет (или он
///   удалён).
abstract interface class RecurringRepository {
  /// Поток живых платежей: сначала по ближайшей дате (закончившиеся в конце),
  /// затем по названию и `id`. Новый список приходит после каждой записи.
  Stream<List<RecurringListItem>> watchAll();

  /// Находит живой платёж по [id] или возвращает `null`.
  Future<RecurringPayment?> findById(String id);

  /// Сохраняет новый [payment]. Служебное `trackedThrough` ставится в день
  /// перед `startsOn` независимо от переданного (ADR 0011, п. 5): платёж на
  /// сегодня сразу попадёт в «К оплате».
  Future<void> create(RecurringPayment payment);

  /// Заменяет поля платежа [payment.id], кроме служебных `trackedThrough` и
  /// `createdAt`. Архивность категории и счёта проверяется только у тех
  /// связей, которые изменились.
  Future<void> update(RecurringPayment payment);

  /// Мягко удаляет платёж [id]. Операции, уже созданные по нему, остаются.
  Future<void> softDelete(String id);

  /// Возвращает удалённый платёж [id] («Отменить»); у живого - ничего не
  /// меняет. Платежа нет вовсе - [ArgumentError].
  Future<void> restore(String id);
}
