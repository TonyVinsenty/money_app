import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';

/// Платёж в списке вместе с ближайшей датой.
final class RecurringListItem {
  const RecurringListItem({required this.payment, required this.nextDue});

  final RecurringPayment payment;

  /// Ближайшая дата платежа не раньше «сегодня»; `null`, если платёж закончился.
  final DateOnly? nextDue;
}

/// Состояние записи «к оплате» (ADR 0011, п. 4).
enum RecurringDueStatus { pending, paid, skipped }

/// Запись «к оплате»: наступившая дата живого платежа.
///
/// Сумма и прочие данные берутся из [payment] как есть сейчас (копии нет).
/// Статус - `pending`, либо `paid`, если созданная операция удалена
/// (ADR 0011, п. 6).
final class RecurringDue {
  const RecurringDue({
    required this.id,
    required this.payment,
    required this.dueOn,
    required this.status,
  });

  final String id;
  final RecurringPayment payment;
  final DateOnly dueOn;
  final RecurringDueStatus status;
}

/// Сколько новых записей на один платёж создаёт один запуск
/// `materializeDue` (ADR 0011, п. 5); остальное догонится следующим запуском.
const maxNewDuesPerRun = 60;

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

  /// Как [create], но `trackedThrough` берётся из [payment] как есть: импорт
  /// CSV ставит день загрузки, чтобы прошлые даты не попали в «К оплате»
  /// (ADR 0011, п. 10). Связи проверяются так же (архив отклоняется).
  Future<void> createImported(RecurringPayment payment);

  /// Заменяет поля платежа [payment.id], кроме служебных `trackedThrough` и
  /// `createdAt`. Архивность категории и счёта проверяется только у тех
  /// связей, которые изменились.
  Future<void> update(RecurringPayment payment);

  /// Мягко удаляет платёж [id]. Операции, уже созданные по нему, остаются.
  Future<void> softDelete(String id);

  /// Создаёт записи «к оплате» для всех наступивших дат живых платежей до
  /// [today] включительно и возвращает, сколько записей добавлено (ADR 0011,
  /// п. 5). Всё в одной транзакции; повторный запуск ничего не добавляет.
  /// Не больше [maxNewDuesPerRun] записей на платёж за запуск.
  Future<int> materializeDue(DateOnly today);

  /// Поток записей «к оплате»: `pending` и `paid` с удалённой операцией, только
  /// у живых платежей. Порядок: дата, затем название, затем `id` записи.
  Stream<List<RecurringDue>> watchDue();

  /// Возвращает удалённый платёж [id] («Отменить»); у живого - ничего не
  /// меняет. Платежа нет вовсе - [ArgumentError].
  Future<void> restore(String id);

  /// «Оплачено» (ADR 0011, п. 6): создаёт операцию через репозиторий операций
  /// и помечает запись [dueId] как `paid` в одной транзакции; возвращает id
  /// операции (для «Отменить» = её мягкое удаление).
  ///
  /// Операция: тип, категория, подкатегория платежа, комментарий = название
  /// платежа, сумма [amount] (валюта - как у платежа), день [day] (не позже
  /// сегодня), счёт [accountId] (`null` - без счёта).
  ///
  /// Статус проверяется внутри транзакции: если запись уже оплачена и её
  /// операция жива, ничего не создаётся и возвращается id той операции
  /// (двойное касание). Оплаченная с удалённой операцией оплачивается заново.
  /// Нарушение правил операции (`TransactionRuleException`, например архивная
  /// категория) оставляет запись как была. `ArgumentError` - записи нет, её
  /// платёж удалён или валюта [amount] не совпала; `StateError` - запись
  /// пропущена (сначала `unskip`).
  Future<String> markPaid(
    String dueId, {
    required Money amount,
    required DateOnly day,
    String? accountId,
  });

  /// «Пропустить»: `pending` (или `paid` с удалённой операцией) становится
  /// `skipped`. У уже пропущенной - ничего не меняет. Оплаченную с живой
  /// операцией пропустить нельзя - `StateError`. Записи нет - `ArgumentError`.
  Future<void> skip(String dueId);

  /// «Отменить» пропуск: `skipped` возвращается в `pending`. У записи в другом
  /// статусе ничего не меняет. Записи нет - `ArgumentError`.
  Future<void> unskip(String dueId);
}
