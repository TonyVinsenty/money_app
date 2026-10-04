import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Хранилище операций: что можно попросить, но не как это устроено.
///
/// Интерфейс живёт в `domain`, а реализация (на drift) — в `data`. Экраны
/// и правила знают только этот интерфейс, поэтому хранилище можно заменить
/// или подменить в тестах фейком.
///
/// Общие ошибки методов:
/// - `TransactionRuleException` — нарушено правило операции (в том числе
///   связи с категориями в `add` и `update`);
/// - `DataCorruptedException` — данные в хранилище испорчены и не
///   превращаются в корректную `Transaction`. Репозиторий сам превращает в
///   неё ошибки конвертеров (`FormatException`): наружу они не выходят.
abstract interface class TransactionsRepository {
  /// Сохраняет новую [transaction].
  ///
  /// `createdAt` и `updatedAt` ставит хранилище.
  ///
  /// Вторая линия защиты: репозиторий сам перечитывает категорию и
  /// подкатегорию из хранилища и проверяет те же связи, что и
  /// `Transaction.create`, ещё до записи (при нарушении база не меняется):
  /// - `TransactionRuleException` с правилом `categoryMustBeTopLevel`,
  ///   `typeKindMismatch`, `subcategoryNotOfCategory` или `categoryArchived`
  ///   (новую операцию нельзя создать в архивной категории или
  ///   подкатегории);
  /// - `ArgumentError`, если категории или подкатегории нет либо она мягко
  ///   удалена;
  /// - `DataCorruptedException`, если данные категории испорчены.
  Future<void> add(Transaction transaction);

  /// Заменяет сохранённую операцию с тем же `id` на [transaction].
  ///
  /// Запись должна существовать и быть живой (не удалённой), иначе
  /// `ArgumentError`. `createdAt` не меняется, `updatedAt` обновляется.
  ///
  /// Связи с категориями перепроверяются так же, как в [add]. Отличие в
  /// архивности: она проверяется (`categoryArchived`) только у только что
  /// изменённых категории и подкатегории. Если операция остаётся в той же,
  /// пусть и архивной, категории, править сумму и комментарий можно.
  Future<void> update(Transaction transaction);

  /// Мягкое удаление операции [id]: строка остаётся в хранилище, но
  /// пропадает из чтения и итогов.
  Future<void> softDelete(String id);

  /// Возвращает мягко удалённую операцию [id] (кнопка «Отменить»).
  Future<void> restore(String id);

  /// Находит операцию по [id] или возвращает `null`.
  ///
  /// Мягко удалённые не возвращаются.
  Future<Transaction?> findById(String id);

  /// Поток последних «живых» операций, не больше [limit].
  ///
  /// Порядок: новые сверху (`occurred_on DESC, occurred_at DESC`), при
  /// равенстве стабильно по `id`. Поток сам выдаёт новый список после каждой
  /// записи.
  Stream<List<Transaction>> watchRecent({int limit = 50});

  /// Все «живые» операции без ограничения по количеству (для экспорта CSV).
  ///
  /// Порядок не задан: его задаёт вызывающий код. Мягко удалённые не входят;
  /// операции в архивных категориях входят, история должна остаться целой.
  /// Испорченная строка даёт `DataCorruptedException`, а не пропуск.
  Future<List<Transaction>> findAllLive();

  /// Поток итога «живых» операций типа [type] за [period] в валюте [currency].
  ///
  /// Обе границы периода (первый и последний день) входят в итог. Суммы
  /// других валют не учитываются: складывать рубли с долларами нельзя
  /// (ADR 0004). Нет операций — ноль в этой валюте.
  Stream<Money> watchTotal({
    required TransactionType type,
    required DateRange period,
    String currency = rubCurrencyCode,
  });

  /// Поток «живых» операций за [period] в валюте [currency], для экрана
  /// «Аналитика» (подсчёты делает `domain` аналитики, ADR 0007).
  ///
  /// Обе границы периода входят. Мягко удалённые не приходят, операции
  /// других валют — тоже. Порядок: по дню, затем по моменту, затем по `id`.
  /// Испорченная строка даёт `DataCorruptedException` в потоке, поток при
  /// этом продолжает работать.
  Stream<List<Transaction>> watchInPeriod(
    DateRange period, {
    String currency = rubCurrencyCode,
  });

  /// Поток самого раннего дня среди «живых» операций; `null`, если их нет.
  ///
  /// Нужен, чтобы знать, как далеко можно листать месяцы назад. Мягко
  /// удалённые не учитываются. Валюта не важна.
  Stream<DateOnly?> watchFirstDay();
}
