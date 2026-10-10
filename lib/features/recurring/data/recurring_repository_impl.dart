import 'package:drift/drift.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/recurring/data/recurring_payment_mapper.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/domain/recurring_repository.dart';
import 'package:money_app/features/recurring/domain/recurring_rules.dart';
import 'package:money_app/features/recurring/domain/recurring_schedule.dart';

/// Реализация [RecurringRepository] на drift. Условие `deleted_at IS NULL`
/// стоит в каждом запросе по живым платежам.
class DriftRecurringRepository implements RecurringRepository {
  DriftRecurringRepository(this._db, {this._clock = const SystemClock()});

  final AppDatabase _db;
  final Clock _clock;

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
      // trackedThrough и createdAt служебные: правка их не трогает.
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
