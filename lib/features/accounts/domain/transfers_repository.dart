import 'package:money_app/features/accounts/domain/transfer.dart';

/// Хранилище переводов между счетами (ADR 0010).
///
/// Общие ошибки методов:
/// - `TransferRuleException` — нарушено правило перевода: `accountArchived`
///   (новый счёт архивный) или `currencyMismatch` (валюта суммы не равна
///   валюте счёта);
/// - `ArgumentError` — перевода или счёта с таким id нет (или он удалён);
/// - `DataCorruptedException` — строка в хранилище испорчена.
abstract interface class TransfersRepository {
  /// Сохраняет новый [transfer]. Оба счёта должны существовать, быть не
  /// архивными и иметь ту же валюту, что и сумма.
  Future<void> add(Transfer transfer);

  /// Для импорта CSV: то же, что [add], но архивные счета разрешены.
  Future<void> addImported(Transfer transfer);

  /// Заменяет перевод с тем же `id`. Валюта и существование счетов
  /// проверяются всегда; архивность — только у счетов, которые меняются:
  /// комментарий, сумму и дату можно править и при архивном старом счёте.
  Future<void> update(Transfer transfer);

  /// Мягко удаляет перевод [id]; повторное удаление ничего не меняет.
  Future<void> softDelete(String id);

  /// Возвращает мягко удалённый перевод («Отменить»); не удалённый — без
  /// изменений.
  Future<void> restore(String id);

  /// Все не удалённые переводы (для экспорта CSV), порядок не гарантируется.
  Future<List<Transfer>> findAllLive();

  /// Поток не удалённых переводов, где [accountId] — «откуда» или «куда»:
  /// от новых к старым (день, момент, `id`), как в «Истории».
  Stream<List<Transfer>> watchForAccount(String accountId);

  /// Поток всех не удалённых переводов (журнал счетов): от новых к старым
  /// (день, момент, `id`).
  Stream<List<Transfer>> watchAll();
}
