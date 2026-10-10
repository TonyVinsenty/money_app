import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/domain/recurring_repository.dart';
import 'package:money_app/features/recurring/domain/recurring_rules.dart';
import 'package:money_app/features/recurring/domain/recurring_schedule.dart';
import 'package:money_app/features/transactions/domain/occurrence.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';
import 'package:money_app/features/transactions/domain/transactions_repository.dart';

/// Фейк регулярных платежей «в памяти»: ведёт себя как `DriftRecurringRepository`
/// (те же проверки в том же порядке, сортировка, служебные поля). Категории и
/// счета, на которые ссылаются платежи, тест кладёт в [categories] и [accounts].
class InMemoryRecurringRepository implements RecurringRepository {
  InMemoryRecurringRepository(this._clock, this.transactions) {
    // Удаление и возврат операции меняют «К оплате».
    transactions.changes.stream.listen((_) => _changes.add(null));
  }

  final Clock _clock;

  /// Операции, которые создаёт `markPaid`.
  final InMemoryLinkedTransactions transactions;
  final categories = <Category>[];
  final accounts = <Account>[];
  final _payments = <RecurringPayment>[];
  final _dues = <_Due>[];
  var _nextDueId = 0;
  final _changes = StreamController<void>.broadcast();

  List<RecurringListItem> _items() {
    final today = _clock.today();
    final items = [
      for (final p in _payments)
        if (!p.isDeleted)
          RecurringListItem(
            payment: p,
            nextDue: nextDueAfter(p, today.addDays(-1)),
          ),
    ];
    items.sort((a, b) {
      final da = a.nextDue;
      final db = b.nextDue;
      if (da != db) {
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      }
      final byTitle = a.payment.title.toLowerCase().compareTo(
        b.payment.title.toLowerCase(),
      );
      return byTitle != 0 ? byTitle : a.payment.id.compareTo(b.payment.id);
    });
    return items;
  }

  @override
  Stream<List<RecurringListItem>> watchAll() => Stream.multi((c) {
    c.add(_items());
    final sub = _changes.stream.listen((_) => c.add(_items()));
    c.onCancel = sub.cancel;
  });

  int _index(String id) => _payments.indexWhere((p) => p.id == id);

  RecurringPayment _requireLive(String id) {
    final i = _index(id);
    if (i < 0 || _payments[i].isDeleted) {
      throw ArgumentError.value(id, 'id', 'recurring payment not found');
    }
    return _payments[i];
  }

  @override
  Future<RecurringPayment?> findById(String id) async {
    final i = _index(id);
    return i < 0 || _payments[i].isDeleted ? null : _payments[i];
  }

  Category _category(String id, String argName) {
    final found = categories.where((c) => c.id == id);
    if (found.isEmpty) {
      throw ArgumentError.value(id, argName, 'category not found');
    }
    return found.first;
  }

  void _checkLinks(
    RecurringPayment p, {
    required bool categoryArchived,
    required bool subcategoryArchived,
    required bool accountArchived,
  }) {
    final category = _category(p.categoryId, 'categoryId');
    if (!category.isTopLevel) {
      throw RecurringRuleException(RecurringRule.categoryMustBeTopLevel);
    }
    if (category.kind.name != p.type.name) {
      throw RecurringRuleException(RecurringRule.typeKindMismatch);
    }
    Category? sub;
    final subId = p.subcategoryId;
    if (subId != null) {
      sub = _category(subId, 'subcategoryId');
      if (sub.parentId != p.categoryId) {
        throw RecurringRuleException(RecurringRule.subcategoryNotOfCategory);
      }
      if (sub.kind != category.kind) {
        throw RecurringRuleException(RecurringRule.typeKindMismatch);
      }
    }
    if ((categoryArchived && category.isArchived) ||
        (subcategoryArchived && sub != null && sub.isArchived)) {
      throw RecurringRuleException(RecurringRule.categoryArchived);
    }
    final accountId = p.accountId;
    if (accountId == null) return;
    final found = accounts.where((a) => a.id == accountId);
    if (found.isEmpty) {
      throw ArgumentError.value(accountId, 'accountId', 'account not found');
    }
    final account = found.first;
    if (account.currency != p.amount.currency) {
      throw RecurringRuleException(RecurringRule.accountCurrencyMismatch);
    }
    if (accountArchived && account.isArchived) {
      throw RecurringRuleException(RecurringRule.accountArchived);
    }
  }

  @override
  Future<void> create(RecurringPayment payment) async {
    _checkLinks(
      payment,
      categoryArchived: true,
      subcategoryArchived: true,
      accountArchived: true,
    );
    final now = _clock.now().toUtc();
    _payments.add(
      _stamped(
        payment.withTrackedThrough(payment.startsOn.addDays(-1)),
        createdAt: now,
        updatedAt: now,
      ),
    );
    _changes.add(null);
  }

  RecurringPayment _stamped(
    RecurringPayment p, {
    required DateTime createdAt,
    required DateTime updatedAt,
    DateTime? deletedAt,
  }) {
    return RecurringPayment(
      id: p.id,
      title: p.title,
      type: p.type,
      amount: p.amount,
      categoryId: p.categoryId,
      subcategoryId: p.subcategoryId,
      accountId: p.accountId,
      unit: p.unit,
      every: p.every,
      startsOn: p.startsOn,
      endsOn: p.endsOn,
      remind: p.remind,
      trackedThrough: p.trackedThrough,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
    );
  }

  @override
  Future<void> update(RecurringPayment payment) async {
    final old = _requireLive(payment.id);
    _checkLinks(
      payment,
      categoryArchived: payment.categoryId != old.categoryId,
      subcategoryArchived: payment.subcategoryId != old.subcategoryId,
      accountArchived: payment.accountId != old.accountId,
    );
    final i = _index(payment.id);
    var tracked = old.trackedThrough;
    if (payment.startsOn != old.startsOn) {
      final today = _clock.today();
      final floor = (payment.startsOn > today ? payment.startsOn : today)
          .addDays(-1);
      if (tracked == null || floor < tracked) tracked = floor;
    }
    _payments[i] = _stamped(
      payment.withTrackedThrough(tracked),
      createdAt: old.createdAt!,
      updatedAt: _clock.now().toUtc(),
    );
    _changes.add(null);
  }

  @override
  Future<void> softDelete(String id) async {
    final old = _requireLive(id);
    final now = _clock.now().toUtc();
    _payments[_index(id)] = _stamped(
      old,
      createdAt: old.createdAt!,
      updatedAt: now,
      deletedAt: now,
    );
    _changes.add(null);
  }

  @override
  Future<int> materializeDue(DateOnly today) async {
    var created = 0;
    for (var i = 0; i < _payments.length; i++) {
      final payment = _payments[i];
      if (payment.isDeleted || payment.startsOn > today) continue;
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
        final exists = _dues.any(
          (d) => d.paymentId == payment.id && d.dueOn == date,
        );
        if (exists) continue;
        // Идентификаторы по возрастанию: порядок «по id» предсказуем.
        final id = 'due-${(_nextDueId++).toString().padLeft(6, '0')}';
        _dues.add(_Due(id, payment.id, date));
        created++;
      }
      if (tracked == null || through > tracked) {
        _payments[i] = _stamped(
          payment.withTrackedThrough(through),
          createdAt: payment.createdAt!,
          updatedAt: payment.updatedAt!,
        );
      }
    }
    _changes.add(null);
    return created;
  }

  List<RecurringDue> _dueItems() {
    final items = <RecurringDue>[];
    for (final d in _dues) {
      final payment = _payments.firstWhere((p) => p.id == d.paymentId);
      if (payment.isDeleted) continue;
      final shown =
          d.status == RecurringDueStatus.pending ||
          (d.status == RecurringDueStatus.paid &&
              transactions.deleted.contains(d.transactionId));
      if (!shown) continue;
      items.add(
        RecurringDue(
          id: d.id,
          payment: payment,
          dueOn: d.dueOn,
          status: d.status,
        ),
      );
    }
    items.sort((a, b) {
      final byDate = a.dueOn.compareTo(b.dueOn);
      if (byDate != 0) return byDate;
      final byTitle = a.payment.title.toLowerCase().compareTo(
        b.payment.title.toLowerCase(),
      );
      return byTitle != 0 ? byTitle : a.id.compareTo(b.id);
    });
    return items;
  }

  @override
  Stream<List<RecurringDue>> watchDue() => Stream.multi((c) {
    c.add(_dueItems());
    final sub = _changes.stream.listen((_) => c.add(_dueItems()));
    c.onCancel = sub.cancel;
  });

  /// Тестовый помощник: переводит запись в [status]; для `paid` операция
  /// считается удалённой, если [transactionDeleted].
  void markDue(
    String paymentId,
    DateOnly dueOn,
    RecurringDueStatus status, {
    bool transactionDeleted = false,
  }) {
    final d = _dues.firstWhere(
      (d) => d.paymentId == paymentId && d.dueOn == dueOn,
    );
    d.status = status;
    d.transactionId = status == RecurringDueStatus.paid
        ? 'tx-$paymentId-${dueOn.toInt()}'
        : null;
    if (transactionDeleted) transactions.deleted.add(d.transactionId!);
    _changes.add(null);
  }

  _Due _requireDue(String id) {
    final found = _dues.where((d) => d.id == id);
    if (found.isEmpty) {
      throw ArgumentError.value(id, 'dueId', 'recurring due not found');
    }
    return found.first;
  }

  bool _paidAlive(_Due d) =>
      d.transactionId != null &&
      !transactions.deleted.contains(d.transactionId);

  @override
  Future<String> markPaid(
    String dueId, {
    required Money amount,
    required DateOnly day,
    String? accountId,
  }) async {
    final due = _requireDue(dueId);
    final payment = _payments.firstWhere((p) => p.id == due.paymentId);
    if (payment.isDeleted) {
      throw ArgumentError.value(dueId, 'dueId', 'recurring payment deleted');
    }
    if (amount.currency != payment.amount.currency) {
      throw ArgumentError.value(amount, 'amount', 'currency differs');
    }
    if (due.status == RecurringDueStatus.skipped) {
      throw StateError('Recurring due "$dueId" is skipped');
    }
    if (_paidAlive(due)) return due.transactionId!;
    final occurrence = Occurrence.onDay(day, clock: _clock);
    final id = 'tx-fake-${transactions.items.length}';
    // Запись занимается до первого await: второе касание видит её оплаченной.
    final before = (due.status, due.transactionId);
    due.status = RecurringDueStatus.paid;
    due.transactionId = id;
    try {
      await transactions.add(
        Transaction(
          id: id,
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
    } catch (_) {
      due.status = before.$1;
      due.transactionId = before.$2;
      rethrow;
    }
    _changes.add(null);
    return id;
  }

  @override
  Future<void> skip(String dueId) async {
    final due = _requireDue(dueId);
    if (due.status == RecurringDueStatus.skipped) return;
    if (_paidAlive(due)) throw StateError('Recurring due "$dueId" is paid');
    due.status = RecurringDueStatus.skipped;
    due.transactionId = null;
    _changes.add(null);
  }

  @override
  Future<void> unskip(String dueId) async {
    final due = _requireDue(dueId);
    if (due.status != RecurringDueStatus.skipped) return;
    due.status = RecurringDueStatus.pending;
    _changes.add(null);
  }

  @override
  Future<void> restore(String id) async {
    final i = _index(id);
    if (i < 0) {
      throw ArgumentError.value(id, 'id', 'recurring payment not found');
    }
    final old = _payments[i];
    if (!old.isDeleted) return;
    _payments[i] = _stamped(
      old.restored(),
      createdAt: old.createdAt!,
      updatedAt: _clock.now().toUtc(),
    );
    _changes.add(null);
  }
}

class _Due {
  _Due(this.id, this.paymentId, this.dueOn);

  final String id;
  final String paymentId;
  final DateOnly dueOn;
  var status = RecurringDueStatus.pending;
  String? transactionId;
}

/// Репозиторий операций «в памяти» для фейка платежей: `add` с проверкой
/// архивности категории, мягкое удаление и возврат. Остальное не нужно.
class InMemoryLinkedTransactions extends Fake
    implements TransactionsRepository {
  InMemoryLinkedTransactions(this._categoryOf);

  final Category? Function(String id) _categoryOf;
  final items = <String, Transaction>{};
  final deleted = <String>{};
  final changes = StreamController<void>.broadcast();

  @override
  Future<void> add(Transaction transaction) async {
    for (final id in [transaction.categoryId, transaction.subcategoryId]) {
      if (id != null && _categoryOf(id)?.isArchived == true) {
        throw TransactionRuleException(TransactionRule.categoryArchived);
      }
    }
    items[transaction.id] = transaction;
  }

  @override
  Future<Transaction?> findById(String id) async =>
      deleted.contains(id) ? null : items[id];

  @override
  Future<List<Transaction>> findAllLive() async => [
    for (final t in items.values)
      if (!deleted.contains(t.id)) t,
  ];

  @override
  Future<void> softDelete(String id) async {
    deleted.add(id);
    changes.add(null);
  }

  @override
  Future<void> restore(String id) async {
    deleted.remove(id);
    changes.add(null);
  }
}
