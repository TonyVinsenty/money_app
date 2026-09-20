import 'dart:async';

import 'package:drift/drift.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/database/converters/transaction_type_converter.dart';
import 'package:money_app/core/errors/data_corrupted_exception.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/transactions/data/transaction_mapper.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/domain/transactions_repository.dart';

/// Реализация [TransactionsRepository] на drift (ADR 0001).
///
/// Наружу отдаёт только доменные [Transaction] и [Money]; классы drift
/// (`TransactionRow`, `TransactionsCompanion`) остаются внутри слоя `data`.
///
/// Условие `deleted_at IS NULL` есть в каждом запросе к «живым» строкам: так
/// SQLite использует частичные индексы схемы (см. `query_plans_test.dart`).
///
/// Ошибки чтения. Конвертеры колонок (`type`, `occurred_on`) работают внутри
/// drift в момент чтения строки и на испорченных данных бросают
/// [FormatException] до того, как строка дойдёт до [transactionFromRow]. Поэтому
/// перехват стоит вокруг самих запросов: в `Future`-методах — [_guard], в
/// потоках — [_translateErrors]. Наружу [FormatException] не выходит.
class DriftTransactionsRepository implements TransactionsRepository {
  // `this._clock` в именованном параметре: снаружи он называется `clock`
  // (приватные именованные параметры, Dart 3.12+).
  DriftTransactionsRepository(this._db, {this._clock = const SystemClock()});

  final AppDatabase _db;
  final Clock _clock;

  /// Нарушение внешнего ключа (несуществующая категория или подкатегория)
  /// не перехватывается: приходит исключение SQLite (ошибка программиста,
  /// а не ситуация для пользователя, ведь категории выбираются из списка).
  @override
  Future<void> add(Transaction transaction) async {
    final now = _clock.now();
    await _db
        .into(_db.transactions)
        .insert(
          transactionToInsertCompanion(
            transaction,
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  @override
  Future<void> update(Transaction transaction) {
    return _db.transaction(() async {
      final state = await _requireState(transaction.id);
      if (state.isDeleted) {
        throw ArgumentError.value(
          transaction.id,
          'transaction',
          'transaction is deleted',
        );
      }
      await (_db.update(
        _db.transactions,
      )..where((t) => t.id.equals(transaction.id))).write(
        transactionToUpdateCompanion(transaction, updatedAt: _clock.now()),
      );
    });
  }

  @override
  Future<void> softDelete(String id) {
    return _db.transaction(() async {
      final state = await _requireState(id);
      if (state.isDeleted) {
        return; // Уже удалена: время удаления остаётся прежним.
      }
      final now = _nowMs();
      await _write(
        id,
        TransactionsCompanion(deletedAt: Value(now), updatedAt: Value(now)),
      );
    });
  }

  @override
  Future<void> restore(String id) {
    return _db.transaction(() async {
      final state = await _requireState(id);
      if (!state.isDeleted) {
        return; // Не удалена: менять нечего.
      }
      // Остальные поля не трогаем: операция возвращается такой, как была.
      await _write(
        id,
        TransactionsCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(_nowMs()),
        ),
      );
    });
  }

  @override
  Future<Transaction?> findById(String id) {
    return _guard(() async {
      final row =
          await (_db.select(_db.transactions)
                ..where((t) => t.deletedAt.isNull() & t.id.equals(id)))
              .getSingleOrNull();
      return row == null ? null : transactionFromRow(row);
    }, what: 'transaction "$id"');
  }

  @override
  Stream<List<Transaction>> watchRecent({int limit = 50}) {
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be positive');
    }
    final query = _db.select(_db.transactions)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.desc(t.occurredOn),
        (t) => OrderingTerm.desc(t.occurredAt),
        (t) => OrderingTerm.desc(t.id),
      ])
      ..limit(limit);
    // Если конвертер или transactionFromRow бросят ошибку, поток получит
    // событие ошибки (DataCorruptedException) и продолжит жить.
    return query
        .watch()
        .map((rows) => rows.map(transactionFromRow).toList())
        .transform(_translateErrors<List<Transaction>>());
  }

  /// Итог считается прямо в SQL и ТОЛЬКО в валюте [currency]: `SUM` без
  /// условия по валюте сложил бы рубли с долларами (ADR 0004).
  ///
  /// Строки здесь не превращаются в сущности, конвертеры не работают, поэтому
  /// строка с испорченным днём (`20261332`) в сумму всё равно входит, если
  /// её число попало в период: SQL сравнивает числа и не проверяет календарь.
  @override
  Stream<Money> watchTotal({
    required TransactionType type,
    required DateRange period,
    String currency = rubCurrencyCode,
  }) {
    // Заодно проверяет код валюты: неверный — ArgumentError прямо сейчас,
    // а не на первом событии потока.
    final zero = Money.zero(currency);
    // `readsFrom` говорит drift, какие таблицы читает запрос: после любой
    // записи в них поток сам выполняет запрос заново.
    return _db
        .customSelect(
          'SELECT COALESCE(SUM(amount_minor), 0) AS total '
          'FROM transactions '
          'WHERE deleted_at IS NULL AND type = ? AND currency = ? '
          'AND occurred_on BETWEEN ? AND ?',
          variables: [
            Variable<String>(const TransactionTypeConverter().toSql(type)),
            Variable<String>(zero.currency),
            Variable<int>(period.start.toInt()),
            Variable<int>(period.end.toInt()),
          ],
          readsFrom: {_db.transactions},
        )
        .watch()
        .map(
          (rows) => Money.fromMinor(rows.single.read<int>('total'), currency),
        );
  }

  /// Данные строки без чтения преобразуемых колонок: удалять и править можно
  /// и испорченную строку (иначе её нельзя было бы убрать).
  Future<_RowState> _requireState(String id) async {
    final table = _db.transactions;
    final row =
        await (_db.selectOnly(table)
              ..addColumns([table.deletedAt])
              ..where(table.id.equals(id)))
            .getSingleOrNull();
    if (row == null) {
      throw ArgumentError.value(id, 'id', 'transaction not found');
    }
    return _RowState(isDeleted: row.read(table.deletedAt) != null);
  }

  Future<void> _write(String id, TransactionsCompanion changes) {
    return (_db.update(
      _db.transactions,
    )..where((t) => t.id.equals(id))).write(changes);
  }

  int _nowMs() => _clock.now().toUtc().millisecondsSinceEpoch;

  /// Выполняет чтение и превращает [FormatException] конвертеров в
  /// [DataCorruptedException]; остальные ошибки проходят как есть.
  Future<T> _guard<T>(Future<T> Function() read, {required String what}) async {
    try {
      return await read();
    } on FormatException catch (error) {
      throw DataCorruptedException(
        'Stored data of $what is corrupted: ${error.message}',
        cause: error,
      );
    }
  }

  /// То же для потока: ошибка потока с [FormatException] заменяется на
  /// [DataCorruptedException]. Остальные события проходят без изменений, а
  /// подписка после ошибки остаётся живой.
  StreamTransformer<T, T> _translateErrors<T>() {
    return StreamTransformer<T, T>.fromHandlers(
      handleError: (error, stackTrace, sink) {
        if (error is FormatException) {
          sink.addError(
            DataCorruptedException(
              'Stored transactions are corrupted: ${error.message}',
              cause: error,
            ),
            stackTrace,
          );
        } else {
          sink.addError(error, stackTrace);
        }
      },
    );
  }
}

/// Что нужно знать о строке перед правкой: удалена ли она.
final class _RowState {
  const _RowState({required this.isDeleted});

  final bool isDeleted;
}
