import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/money.dart';
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
/// - `TransactionRuleException` — нарушено правило операции;
/// - `DataCorruptedException` — данные в хранилище испорчены и не
///   превращаются в корректную `Transaction`. Репозиторий сам превращает в
///   неё ошибки конвертеров (`FormatException`): наружу они не выходят.
abstract interface class TransactionsRepository {
  /// Сохраняет новую [transaction].
  ///
  /// `createdAt` и `updatedAt` ставит хранилище.
  Future<void> add(Transaction transaction);

  /// Заменяет сохранённую операцию с тем же `id` на [transaction].
  ///
  /// Запись должна существовать и быть живой (не удалённой). `createdAt`
  /// не меняется, `updatedAt` обновляется.
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
}
