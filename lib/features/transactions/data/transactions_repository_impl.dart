import 'dart:async';

import 'package:drift/drift.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/database/converters/date_only_converter.dart';
import 'package:money_app/core/database/converters/transaction_type_converter.dart';
import 'package:money_app/core/errors/data_corrupted_exception.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/data/transaction_mapper.dart';
import 'package:money_app/features/transactions/domain/category_kind_mapping.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';
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

  /// Вторая линия защиты: перед записью, в той же транзакции, репозиторий сам
  /// перечитывает категорию и подкатегорию и проверяет связи (см.
  /// [_checkLinks]). Нарушения бросают [TransactionRuleException] до записи.
  /// Категория, которой нет (или она мягко удалена), — [ArgumentError].
  @override
  Future<void> add(Transaction transaction) =>
      _insert(transaction, allowArchivedCategories: false);

  /// Для импорта CSV: то же, что [add], но архивные категории разрешены.
  @override
  Future<void> addImported(Transaction transaction) =>
      _insert(transaction, allowArchivedCategories: true);

  Future<void> _insert(
    Transaction transaction, {
    required bool allowArchivedCategories,
  }) {
    return _db.transaction(() async {
      await _checkLinks(
        transaction,
        checkCategoryArchived: !allowArchivedCategories,
        checkSubcategoryArchived:
            !allowArchivedCategories && transaction.subcategoryId != null,
      );
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
    });
  }

  /// Архивность проверяется только у ИЗМЕНЁННЫХ `category_id` и
  /// `subcategory_id`: если операция остаётся в той же (теперь архивной)
  /// категории, править сумму и комментарий можно.
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
      await _checkLinks(
        transaction,
        checkCategoryArchived: transaction.categoryId != state.categoryId,
        checkSubcategoryArchived:
            transaction.subcategoryId != null &&
            transaction.subcategoryId != state.subcategoryId,
      );
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
  Future<List<Transaction>> findAllLive() {
    return _guard(() async {
      final rows = await (_db.select(
        _db.transactions,
      )..where((t) => t.deletedAt.isNull())).get();
      return rows.map(transactionFromRow).toList();
    }, what: 'all transactions');
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

  /// Строки за период в одной валюте. Фильтр по `occurred_on` идёт через
  /// конвертер, то есть границы сравниваются как ГГГГММДД, и попадает в
  /// индекс `transactions_occurred_on_at` (план проверяет `query_plans_test`).
  @override
  Stream<List<Transaction>> watchInPeriod(
    DateRange period, {
    String currency = rubCurrencyCode,
  }) {
    return _watchLive(
      currency,
      (t) => t.occurredOn.isBetweenValues(
        period.start.toInt(),
        period.end.toInt(),
      ),
    );
  }

  @override
  Stream<List<Transaction>> watchAll({String currency = rubCurrencyCode}) =>
      _watchLive(currency, null);

  /// Живые строки в валюте [currency] (и под условием [where], если оно
  /// есть) по дню, моменту и `id`.
  Stream<List<Transaction>> _watchLive(
    String currency,
    Expression<bool> Function($TransactionsTable t)? where,
  ) {
    // Заодно проверяет код валюты: неверный — ArgumentError сразу.
    Money.zero(currency);
    final query = _db.select(_db.transactions)
      ..where((t) {
        final live = t.deletedAt.isNull() & t.currency.equals(currency);
        return where == null ? live : live & where(t);
      })
      ..orderBy([
        (t) => OrderingTerm.asc(t.occurredOn),
        (t) => OrderingTerm.asc(t.occurredAt),
        (t) => OrderingTerm.asc(t.id),
      ]);
    // Ошибки чтения и сборки — как в watchRecent: событием потока.
    return query
        .watch()
        .map((rows) => rows.map(transactionFromRow).toList())
        .transform(_translateErrors<List<Transaction>>());
  }

  /// Самый ранний день среди «живых» операций (любой валюты). `MIN` по
  /// частичному индексу `transactions_occurred_on_at`; нет строк — `null`.
  @override
  Stream<DateOnly?> watchFirstDay() {
    return _db
        .customSelect(
          'SELECT MIN(occurred_on) AS first_day FROM transactions '
          'WHERE deleted_at IS NULL',
          readsFrom: {_db.transactions},
        )
        .watch()
        .map((rows) {
          final value = rows.single.read<int?>('first_day');
          return value == null
              ? null
              : const DateOnlyConverter().fromSql(value);
        })
        .transform(_translateErrors<DateOnly?>());
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
              ..addColumns([
                table.deletedAt,
                table.categoryId,
                table.subcategoryId,
              ])
              ..where(table.id.equals(id)))
            .getSingleOrNull();
    if (row == null) {
      throw ArgumentError.value(id, 'id', 'transaction not found');
    }
    return _RowState(
      isDeleted: row.read(table.deletedAt) != null,
      categoryId: row.read(table.categoryId)!,
      subcategoryId: row.read(table.subcategoryId),
    );
  }

  /// Проверяет те же связи, что `Transaction.create`, но по строкам базы.
  /// Порядок: категория есть -> верхнего уровня -> вид совпадает с типом ->
  /// подкатегория есть -> её родитель именно эта категория -> вид совпадает
  /// -> архивность (только для помеченных флагами).
  Future<void> _checkLinks(
    Transaction transaction, {
    required bool checkCategoryArchived,
    required bool checkSubcategoryArchived,
  }) async {
    final category = await _requireCategory(
      transaction.categoryId,
      'categoryId',
    );
    if (category.parentId != null) {
      throw TransactionRuleException(TransactionRule.categoryMustBeTopLevel);
    }
    if (category.kind.transactionType != transaction.type) {
      throw TransactionRuleException(TransactionRule.typeKindMismatch);
    }
    final subcategoryId = transaction.subcategoryId;
    _CategoryInfo? subcategory;
    if (subcategoryId != null) {
      subcategory = await _requireCategory(subcategoryId, 'subcategoryId');
      if (subcategory.parentId != transaction.categoryId) {
        throw TransactionRuleException(
          TransactionRule.subcategoryNotOfCategory,
        );
      }
      if (subcategory.kind != category.kind) {
        throw TransactionRuleException(TransactionRule.typeKindMismatch);
      }
    }
    if ((checkCategoryArchived && category.isArchived) ||
        (checkSubcategoryArchived &&
            subcategory != null &&
            subcategory.isArchived)) {
      throw TransactionRuleException(TransactionRule.categoryArchived);
    }
  }

  /// Читает нужные колонки категории напрямую; мягко удалённая категория
  /// считается несуществующей ([ArgumentError]).
  Future<_CategoryInfo> _requireCategory(String id, String argName) async {
    final table = _db.categories;
    final row =
        await (_db.selectOnly(table)
              ..addColumns([table.parentId, table.kind, table.archivedAt])
              ..where(table.deletedAt.isNull() & table.id.equals(id)))
            .getSingleOrNull();
    if (row == null) {
      throw ArgumentError.value(id, argName, 'category not found');
    }
    final kindText = row.read(table.kind)!;
    final CategoryKind kind;
    switch (kindText) {
      case 'income':
        kind = CategoryKind.income;
      case 'expense':
        kind = CategoryKind.expense;
      default:
        throw DataCorruptedException(
          'Category row "$id" is corrupted: unknown kind "$kindText"',
        );
    }
    return _CategoryInfo(
      parentId: row.read(table.parentId),
      kind: kind,
      isArchived: row.read(table.archivedAt) != null,
    );
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

/// Что нужно знать о строке перед правкой: удалена ли она и в каких
/// категориях лежит сейчас.
final class _RowState {
  const _RowState({
    required this.isDeleted,
    required this.categoryId,
    required this.subcategoryId,
  });

  final bool isDeleted;
  final String categoryId;
  final String? subcategoryId;
}

/// Колонки категории, нужные для проверки связей операции.
final class _CategoryInfo {
  const _CategoryInfo({
    required this.parentId,
    required this.kind,
    required this.isArchived,
  });

  final String? parentId;
  final CategoryKind kind;
  final bool isArchived;
}
