import 'package:drift/drift.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/errors/data_corrupted_exception.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/recurring/data/recurring_payment_mapper.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/domain/recurring_repository.dart';
import 'package:money_app/features/recurring/domain/recurring_rules.dart';
import 'package:money_app/features/recurring/domain/recurring_schedule.dart';
import 'package:money_app/features/transactions/domain/occurrence.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transactions_repository.dart';

/// Запрос «К оплате»: записи живых платежей, ожидающие оплаты, и оплаченные с
/// удалённой операцией (ADR 0011, п. 6). Вынесен отдельно, чтобы тест плана
/// запроса смотрел на тот же запрос.
JoinedSelectStatement<HasResultSet, dynamic> recurringDueQuery(AppDatabase db) {
  final d = db.recurringDues;
  final p = db.recurringPayments;
  final t = db.transactions;
  return db.select(d).join([
    innerJoin(p, p.id.equalsExp(d.paymentId)),
    leftOuterJoin(t, t.id.equalsExp(d.transactionId)),
  ])..where(
    p.deletedAt.isNull() &
        (d.status.equals('pending') |
            (d.status.equals('paid') & t.deletedAt.isNotNull())),
  );
}

/// Реализация [RecurringRepository] на drift. Условие `deleted_at IS NULL`
/// стоит в каждом запросе по живым платежам.
class DriftRecurringRepository implements RecurringRepository {
  DriftRecurringRepository(
    this._db,
    this._transactions, {
    this._clock = const SystemClock(),
    this._ids = const UuidV7Generator(),
  });

  final AppDatabase _db;
  final TransactionsRepository _transactions;
  final Clock _clock;
  final IdGenerator _ids;

  @override
  Stream<List<RecurringListItem>> watchAll() {
    final query = _db.select(_db.recurringPayments)
      ..where((p) => p.deletedAt.isNull());
    return query.watch().map((rows) {
      final today = _clock.today();
      final items = [
        for (final row in rows) _item(recurringPaymentFromRow(row), today),
      ];
      items.sort(_compareItems);
      return items;
    });
  }

  RecurringListItem _item(RecurringPayment payment, DateOnly today) {
    return RecurringListItem(
      payment: payment,
      nextDue: nextDueAfter(payment, today.addDays(-1)),
    );
  }

  static int _compareItems(RecurringListItem a, RecurringListItem b) {
    final da = a.nextDue;
    final db = b.nextDue;
    if (da != db) {
      if (da == null) return 1; // Закончившиеся - в конец.
      if (db == null) return -1;
      return da.compareTo(db);
    }
    final byTitle = a.payment.title.toLowerCase().compareTo(
      b.payment.title.toLowerCase(),
    );
    return byTitle != 0 ? byTitle : a.payment.id.compareTo(b.payment.id);
  }

  @override
  Future<RecurringPayment?> findById(String id) async {
    final row = await _liveRow(id);
    return row == null ? null : recurringPaymentFromRow(row);
  }

  @override
  Future<void> create(RecurringPayment payment) {
    return _db.transaction(() async {
      await _checkLinks(
        payment,
        checkCategoryArchived: true,
        checkSubcategoryArchived: true,
        checkAccountArchived: true,
      );
      final now = _clock.now();
      await _db
          .into(_db.recurringPayments)
          .insert(
            recurringPaymentToCompanion(
              payment.withTrackedThrough(payment.startsOn.addDays(-1)),
              createdAt: now,
              updatedAt: now,
            ),
          );
    });
  }

  @override
  Future<void> update(RecurringPayment payment) {
    return _db.transaction(() async {
      final old = await _requireLiveRow(payment.id);
      await _checkLinks(
        payment,
        checkCategoryArchived: payment.categoryId != old.categoryId,
        checkSubcategoryArchived: payment.subcategoryId != old.subcategoryId,
        checkAccountArchived: payment.accountId != old.accountId,
      );
      // createdAt служебный: правка его не трогает. trackedThrough сдвигается
      // назад только при переносе startsOn, чтобы новые даты не потерялись.
      var tracked = old.trackedThrough;
      if (payment.startsOn != old.startsOn) {
        final today = _clock.today();
        final floor = (payment.startsOn > today ? payment.startsOn : today)
            .addDays(-1);
        if (tracked == null || floor < tracked) tracked = floor;
      }
      await _write(
        payment.id,
        RecurringPaymentsCompanion(
          title: Value(payment.title),
          type: Value(payment.type),
          amountMinor: Value(payment.amount.minorUnits),
          currency: Value(payment.amount.currency),
          categoryId: Value(payment.categoryId),
          subcategoryId: Value(payment.subcategoryId),
          accountId: Value(payment.accountId),
          unit: Value(payment.unit.name),
          every: Value(payment.every),
          startsOn: Value(payment.startsOn),
          endsOn: Value(payment.endsOn),
          remind: Value(payment.remind),
          trackedThrough: Value(tracked),
          updatedAt: Value(_nowMs()),
        ),
      );
    });
  }

  @override
  Future<void> softDelete(String id) {
    return _db.transaction(() async {
      await _requireLiveRow(id);
      final now = _nowMs();
      await _write(
        id,
        RecurringPaymentsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    });
  }

  @override
  Future<int> materializeDue(DateOnly today) {
    return _db.transaction(() async {
      final rows = await (_db.select(
        _db.recurringPayments,
      )..where((p) => p.deletedAt.isNull())).get();
      final nowMs = _nowMs();
      var created = 0;
      for (final row in rows) {
        final RecurringPayment payment;
        try {
          payment = recurringPaymentFromRow(row);
        } on DataCorruptedException {
          continue; // Испорченный платёж пропускаем, остальные обрабатываем.
        }
        // Платёж из будущего: записей нет, trackedThrough не трогаем.
        if (payment.startsOn > today) continue;
        final tracked = payment.trackedThrough;
        final next = tracked?.addDays(1);
        final from = next == null || next < payment.startsOn
            ? payment.startsOn
            : next;
        final end = payment.endsOn;
        final to = end != null && end < today ? end : today;
        var dates = dueDates(payment, from, to);
        var through = today;
        if (dates.length > maxNewDuesPerRun) {
          dates = dates.sublist(0, maxNewDuesPerRun);
          through = dates.last;
        }
        for (final date in dates) {
          created += await _db.customUpdate(
            'INSERT INTO recurring_dues (id, payment_id, due_on, status, '
            'created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?) '
            'ON CONFLICT DO NOTHING',
            variables: [
              Variable<String>(_ids.newId()),
              Variable<String>(payment.id),
              Variable<int>(date.toInt()),
              Variable<String>(RecurringDueStatus.pending.name),
              Variable<int>(nowMs),
              Variable<int>(nowMs),
            ],
            updates: {_db.recurringDues},
          );
        }
        if (tracked == null || through > tracked) {
          await _write(
            payment.id,
            RecurringPaymentsCompanion(trackedThrough: Value(through)),
          );
        }
      }
      return created;
    });
  }

  @override
  Stream<List<RecurringDue>> watchDue() {
    return recurringDueQuery(_db).watch().map((rows) {
      final dues = <RecurringDue>[];
      for (final row in rows) {
        final due = row.readTable(_db.recurringDues);
        dues.add(
          RecurringDue(
            id: due.id,
            payment: recurringPaymentFromRow(
              row.readTable(_db.recurringPayments),
            ),
            dueOn: due.dueOn,
            status: _statusFromSql(due),
          ),
        );
      }
      dues.sort(_compareDues);
      return dues;
    });
  }

  static RecurringDueStatus _statusFromSql(RecurringDueRow row) {
    for (final status in RecurringDueStatus.values) {
      if (status.name == row.status) return status;
    }
    throw DataCorruptedException(
      'Recurring due row "${row.id}" has bad status "${row.status}"',
    );
  }

  static int _compareDues(RecurringDue a, RecurringDue b) {
    final byDate = a.dueOn.compareTo(b.dueOn);
    if (byDate != 0) return byDate;
    final byTitle = a.payment.title.toLowerCase().compareTo(
      b.payment.title.toLowerCase(),
    );
    return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
  }

  @override
  Future<void> restore(String id) {
    return _db.transaction(() async {
      final row = await (_db.select(
        _db.recurringPayments,
      )..where((p) => p.id.equals(id))).getSingleOrNull();
      if (row == null) {
        throw ArgumentError.value(id, 'id', 'recurring payment not found');
      }
      if (row.deletedAt == null) return;
      await _write(
        id,
        RecurringPaymentsCompanion(
          deletedAt: const Value(null),
          updatedAt: Value(_nowMs()),
        ),
      );
    });
  }

  @override
  Future<String> markPaid(
    String dueId, {
    required Money amount,
    required DateOnly day,
    String? accountId,
  }) {
    return _db.transaction(() async {
      final due = await _requireDue(dueId);
      final payment = recurringPaymentFromRow(await _paymentRowOf(due));
      if (amount.currency != payment.amount.currency) {
        throw ArgumentError.value(amount, 'amount', 'currency differs');
      }
      if (due.status == RecurringDueStatus.skipped.name) {
        throw StateError('Recurring due "$dueId" is skipped');
      }
      final oldId = due.transactionId;
      if (oldId != null && !await _isTransactionDeleted(oldId)) {
        return oldId; // Уже оплачено: вторая операция не создаётся.
      }
      final occurrence = Occurrence.onDay(day, clock: _clock);
      final transactionId = _ids.newId();
      await _transactions.add(
        Transaction(
          id: transactionId,
          type: payment.type,
          amount: amount,
          occurredOn: occurrence.occurredOn,
          occurredAt: occurrence.occurredAt,
          categoryId: payment.categoryId,
          subcategoryId: payment.subcategoryId,
          note: payment.title,
          accountId: accountId,
        ),
      );
      final now = _nowMs();
      await _writeDue(
        dueId,
        RecurringDuesCompanion(
          status: Value(RecurringDueStatus.paid.name),
          transactionId: Value(transactionId),
          resolvedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      return transactionId;
    });
  }

  @override
  Future<void> skip(String dueId) {
    return _db.transaction(() async {
      final due = await _requireDue(dueId);
      if (due.status == RecurringDueStatus.skipped.name) return;
      final id = due.transactionId;
      if (id != null && !await _isTransactionDeleted(id)) {
        throw StateError('Recurring due "$dueId" is paid');
      }
      final now = _nowMs();
      // CHECK: paid <=> есть операция; у skipped связь с операцией пустая.
      await _writeDue(
        dueId,
        RecurringDuesCompanion(
          status: Value(RecurringDueStatus.skipped.name),
          transactionId: const Value(null),
          resolvedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
    });
  }

  @override
  Future<void> unskip(String dueId) {
    return _db.transaction(() async {
      final due = await _requireDue(dueId);
      if (due.status != RecurringDueStatus.skipped.name) return;
      await _writeDue(
        dueId,
        RecurringDuesCompanion(
          status: Value(RecurringDueStatus.pending.name),
          resolvedAt: const Value(null),
          updatedAt: Value(_nowMs()),
        ),
      );
    });
  }

  Future<RecurringDueRow> _requireDue(String id) async {
    final row = await (_db.select(
      _db.recurringDues,
    )..where((d) => d.id.equals(id))).getSingleOrNull();
    if (row == null) {
      throw ArgumentError.value(id, 'dueId', 'recurring due not found');
    }
    return row;
  }

  Future<RecurringPaymentRow> _paymentRowOf(RecurringDueRow due) async {
    final row = await _liveRow(due.paymentId);
    if (row == null) {
      throw ArgumentError.value(due.id, 'dueId', 'recurring payment deleted');
    }
    return row;
  }

  Future<bool> _isTransactionDeleted(String id) async {
    final t = _db.transactions;
    final row =
        await (_db.selectOnly(t)
              ..addColumns([t.deletedAt])
              ..where(t.id.equals(id)))
            .getSingleOrNull();
    return row == null || row.read(t.deletedAt) != null;
  }

  Future<void> _writeDue(String id, RecurringDuesCompanion changes) {
    return (_db.update(
      _db.recurringDues,
    )..where((d) => d.id.equals(id))).write(changes);
  }

  /// Проверяет связи платежа по сырым строкам: категория есть -> верхнего
  /// уровня -> вид совпадает с типом -> подкатегория есть -> её родитель -
  /// эта категория -> вид -> архив; счёт есть -> валюта -> архив.
  Future<void> _checkLinks(
    RecurringPayment payment, {
    required bool checkCategoryArchived,
    required bool checkSubcategoryArchived,
    required bool checkAccountArchived,
  }) async {
    final category = await _categoryInfo(payment.categoryId, 'categoryId');
    if (category.parentId != null) {
      throw RecurringRuleException(RecurringRule.categoryMustBeTopLevel);
    }
    if (category.kind != payment.type.name) {
      throw RecurringRuleException(RecurringRule.typeKindMismatch);
    }
    final subcategoryId = payment.subcategoryId;
    _CategoryInfo? subcategory;
    if (subcategoryId != null) {
      subcategory = await _categoryInfo(subcategoryId, 'subcategoryId');
      if (subcategory.parentId != payment.categoryId) {
        throw RecurringRuleException(RecurringRule.subcategoryNotOfCategory);
      }
      if (subcategory.kind != category.kind) {
        throw RecurringRuleException(RecurringRule.typeKindMismatch);
      }
    }
    if ((checkCategoryArchived && category.isArchived) ||
        (checkSubcategoryArchived &&
            subcategory != null &&
            subcategory.isArchived)) {
      throw RecurringRuleException(RecurringRule.categoryArchived);
    }

    final accountId = payment.accountId;
    if (accountId == null) return;
    final table = _db.accounts;
    final account =
        await (_db.selectOnly(table)
              ..addColumns([table.currency, table.archivedAt])
              ..where(table.deletedAt.isNull() & table.id.equals(accountId)))
            .getSingleOrNull();
    if (account == null) {
      throw ArgumentError.value(accountId, 'accountId', 'account not found');
    }
    if (account.read(table.currency) != payment.amount.currency) {
      throw RecurringRuleException(RecurringRule.accountCurrencyMismatch);
    }
    if (checkAccountArchived && account.read(table.archivedAt) != null) {
      throw RecurringRuleException(RecurringRule.accountArchived);
    }
  }

  Future<_CategoryInfo> _categoryInfo(String id, String argName) async {
    final table = _db.categories;
    final row =
        await (_db.selectOnly(table)
              ..addColumns([table.parentId, table.kind, table.archivedAt])
              ..where(table.deletedAt.isNull() & table.id.equals(id)))
            .getSingleOrNull();
    if (row == null) {
      throw ArgumentError.value(id, argName, 'category not found');
    }
    return _CategoryInfo(
      parentId: row.read(table.parentId),
      kind: row.read(table.kind)!,
      isArchived: row.read(table.archivedAt) != null,
    );
  }

  Future<RecurringPaymentRow?> _liveRow(String id) {
    return (_db.select(
      _db.recurringPayments,
    )..where((p) => p.deletedAt.isNull() & p.id.equals(id))).getSingleOrNull();
  }

  Future<RecurringPaymentRow> _requireLiveRow(String id) async {
    final row = await _liveRow(id);
    if (row == null) {
      throw ArgumentError.value(id, 'id', 'recurring payment not found');
    }
    return row;
  }

  Future<void> _write(String id, RecurringPaymentsCompanion changes) {
    return (_db.update(
      _db.recurringPayments,
    )..where((p) => p.id.equals(id))).write(changes);
  }

  int _nowMs() => _clock.now().toUtc().millisecondsSinceEpoch;
}

/// Колонки категории, нужные для проверки связей платежа.
final class _CategoryInfo {
  const _CategoryInfo({
    required this.parentId,
    required this.kind,
    required this.isArchived,
  });

  final String? parentId;
  final String kind;
  final bool isArchived;
}
