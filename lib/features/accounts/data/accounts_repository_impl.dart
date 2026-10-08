import 'package:drift/drift.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/features/accounts/data/account_mapper.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/account_balances.dart';
import 'package:money_app/features/accounts/domain/account_rules.dart';
import 'package:money_app/features/accounts/domain/accounts_repository.dart';

/// Реализация [AccountsRepository] на drift. Условие `deleted_at IS NULL`
/// стоит в каждом запросе: только так SQLite берёт частичный индекс.
class DriftAccountsRepository implements AccountsRepository {
  DriftAccountsRepository(this._db, {this._clock = const SystemClock()});

  final AppDatabase _db;
  final Clock _clock;

  @override
  Stream<List<Account>> watchAll() {
    final query = _db.select(_db.accounts)
      ..where((a) => a.deletedAt.isNull())
      ..orderBy(_stableOrder);
    return query.watch().map((rows) => rows.map(accountFromRow).toList());
  }

  @override
  Stream<Map<String, Money>> watchBalances() {
    // Пустой SELECT нужен лишь как «подписка»: drift перезапускает его при
    // записи в любую из трёх таблиц, а сами суммы считает _loadBalances.
    return _db
        .customSelect(
          'SELECT 1',
          readsFrom: {_db.accounts, _db.transactions, _db.transfers},
        )
        .watch()
        .asyncMap((_) => _db.transaction(_loadBalances));
  }

  Future<Map<String, Money>> _loadBalances() async {
    final accounts =
        (await (_db.select(_db.accounts)
                  ..where((a) => a.deletedAt.isNull())
                  ..orderBy(_stableOrder))
                .get())
            .map(accountFromRow)
            .toList();

    // Движения считаем отдельно для каждой валюты, которая есть у счетов.
    final flows = <String, AccountFlows>{};
    for (final currency in {for (final a in accounts) a.currency}) {
      flows.addAll(
        await _loadFlows([
          for (final a in accounts)
            if (a.currency == currency) a.id,
        ], currency),
      );
    }
    return computeAccountBalances(accounts, flows);
  }

  /// Движения по счетам [ids] в валюте [currency]: SUM-запросы по операциям и
  /// переводам. Для счёта без движений в карте лежат нули.
  Future<Map<String, AccountFlows>> _loadFlows(
    Iterable<String> ids,
    String currency,
  ) async {
    Future<List<QueryRow>> sums(String sql) {
      return _db
          .customSelect(sql, variables: [Variable<String>(currency)])
          .get();
    }

    // `account_id IS NOT NULL` и `deleted_at IS NULL` нужны, чтобы SQLite
    // взяла частичные индексы (transactions_account, transfers_*_account).
    final operations = await sums(
      'SELECT account_id AS id, type, SUM(amount_minor) AS total '
      'FROM transactions WHERE deleted_at IS NULL '
      'AND account_id IS NOT NULL AND currency = ? '
      'GROUP BY account_id, type',
    );
    final outgoing = await sums(
      'SELECT from_account_id AS id, SUM(amount_minor) AS total '
      'FROM transfers WHERE deleted_at IS NULL AND currency = ? '
      'GROUP BY from_account_id',
    );
    final incoming = await sums(
      'SELECT to_account_id AS id, SUM(amount_minor) AS total '
      'FROM transfers WHERE deleted_at IS NULL AND currency = ? '
      'GROUP BY to_account_id',
    );

    final income = <String, int>{};
    final expense = <String, int>{};
    for (final row in operations) {
      final target = row.read<String>('type') == 'income' ? income : expense;
      target[row.read<String>('id')] = row.read<int>('total');
    }
    int sumOf(List<QueryRow> rows, String id) {
      for (final row in rows) {
        if (row.read<String>('id') == id) return row.read<int>('total');
      }
      return 0;
    }

    Money money(int minor) => Money.fromMinor(minor, currency);
    return {
      for (final id in ids)
        id: AccountFlows(
          income: money(income[id] ?? 0),
          expense: money(expense[id] ?? 0),
          transfersIn: money(sumOf(incoming, id)),
          transfersOut: money(sumOf(outgoing, id)),
        ),
    };
  }

  @override
  Future<Account?> findById(String id) async {
    final row = await _row(id);
    return row == null ? null : accountFromRow(row);
  }

  @override
  Future<int> nextSortOrder() async {
    final rows = await (_db.select(
      _db.accounts,
    )..where((a) => a.deletedAt.isNull())).get();
    var next = 0;
    for (final row in rows) {
      if (row.sortOrder >= next) next = row.sortOrder + 1;
    }
    return next;
  }

  @override
  Future<void> create(Account account) {
    return _db.transaction(() async {
      await _checkUniqueName(account.name);
      await _checkCurrencyDigits(account);
      final now = _clock.now();
      await _db
          .into(_db.accounts)
          .insert(accountToCompanion(account, createdAt: now, updatedAt: now));
    });
  }

  @override
  Future<void> update(
    String id, {
    required String name,
    required String iconKey,
  }) {
    return _db.transaction(() async {
      // Строку в Account не собираем: испорченную можно починить правкой.
      await _requireRow(id);
      final checkedName = Account.checkedName(name);
      if (iconKey.trim().isEmpty) {
        throw AccountRuleException(AccountRule.emptyIconKey);
      }
      await _checkUniqueName(checkedName, selfId: id);
      await _updateRow(
        id,
        AccountsCompanion(
          name: Value(checkedName),
          iconKey: Value(iconKey),
          updatedAt: Value(_nowMs()),
        ),
      );
    });
  }

  @override
  Future<void> setOpeningBalance(String id, Money openingBalance) {
    return _db.transaction(() async {
      final row = await _requireRow(id);
      // Валюта счёта не меняется: иначе его операции перестанут сходиться.
      if (row.currency != openingBalance.currency) {
        throw ArgumentError.value(
          openingBalance.currency,
          'openingBalance',
          'currency differs from the account currency',
        );
      }
      await _updateRow(
        id,
        AccountsCompanion(
          openingBalanceMinor: Value(openingBalance.minorUnits),
          updatedAt: Value(_nowMs()),
        ),
      );
    });
  }

  @override
  Future<void> adjustCurrentBalance(String id, Money entered) {
    return _db.transaction(() async {
      final row = await _requireRow(id);
      if (row.currency != entered.currency) {
        throw ArgumentError.value(
          entered.currency,
          'entered',
          'currency differs from the account currency',
        );
      }
      // Движения и запись — в одной транзакции: между ними ничего не вклинится.
      final flows = (await _loadFlows([id], row.currency))[id]!;
      await _updateRow(
        id,
        AccountsCompanion(
          openingBalanceMinor: Value(
            openingForCurrentBalance(entered, flows).minorUnits,
          ),
          updatedAt: Value(_nowMs()),
        ),
      );
    });
  }

  @override
  Future<void> reorder(List<String> orderedIds) {
    if (orderedIds.isEmpty) {
      return Future<void>.value();
    }
    if (orderedIds.toSet().length != orderedIds.length) {
      return Future<void>.error(
        ArgumentError.value(orderedIds, 'orderedIds', 'contains duplicates'),
      );
    }
    return _db.transaction(() async {
      final all =
          await (_db.select(_db.accounts)
                ..where((a) => a.deletedAt.isNull())
                ..orderBy(_stableOrder))
              .get();
      final byId = {for (final row in all) row.id: row};
      for (final id in orderedIds) {
        if (!byId.containsKey(id)) {
          throw ArgumentError.value(id, 'orderedIds', 'account not found');
        }
      }
      final requested = orderedIds.toSet();
      final finalOrder = [
        for (final id in orderedIds) byId[id]!,
        for (final row in all)
          if (!requested.contains(row.id)) row,
      ];
      final now = _nowMs();
      for (var i = 0; i < finalOrder.length; i++) {
        final row = finalOrder[i];
        if (row.sortOrder == i) continue; // Уже на месте.
        await _updateRow(
          row.id,
          AccountsCompanion(sortOrder: Value(i), updatedAt: Value(now)),
        );
      }
    });
  }

  @override
  Future<void> archive(String id) {
    return _db.transaction(() async {
      final row = await _requireRow(id);
      if (row.archivedAt != null) return;
      final now = _nowMs();
      await _updateRow(
        id,
        AccountsCompanion(archivedAt: Value(now), updatedAt: Value(now)),
      );
    });
  }

  @override
  Future<void> restore(String id) {
    return _db.transaction(() async {
      final row = await _requireRow(id);
      if (row.archivedAt == null) return;
      await _checkUniqueName(row.name, selfId: id);
      await _updateRow(
        id,
        AccountsCompanion(
          archivedAt: const Value(null),
          updatedAt: Value(_nowMs()),
        ),
      );
    });
  }

  static final List<OrderingTerm Function($AccountsTable)> _stableOrder = [
    (a) => OrderingTerm.asc(a.sortOrder),
    (a) => OrderingTerm.asc(a.createdAt),
    (a) => OrderingTerm.asc(a.id),
  ];

  Future<AccountRow?> _row(String id) {
    return (_db.select(
      _db.accounts,
    )..where((a) => a.deletedAt.isNull() & a.id.equals(id))).getSingleOrNull();
  }

  Future<AccountRow> _requireRow(String id) async {
    final row = await _row(id);
    if (row == null) {
      throw ArgumentError.value(id, 'id', 'account not found');
    }
    return row;
  }

  /// Дубль ищем по сырым строкам не архивных счетов (кроме [selfId]):
  /// испорченный сосед не должен мешать.
  Future<void> _checkUniqueName(String name, {String? selfId}) async {
    final rows =
        await (_db.select(_db.accounts)..where(
              (a) =>
                  a.deletedAt.isNull() &
                  a.archivedAt.isNull() &
                  (selfId == null
                      ? const Constant(true)
                      : a.id.equals(selfId).not()),
            ))
            .get();
    final key = accountNameKey(name);
    if (rows.any((row) => accountNameKey(row.name) == key)) {
      throw AccountRuleException(AccountRule.duplicateName);
    }
  }

  /// Знаки валюты: как в каталоге или как у любого (и архивного) счёта
  /// с тем же кодом; смотрим сырые строки, испорченный сосед не мешает.
  Future<void> _checkCurrencyDigits(Account account) async {
    final rows = await (_db.select(
      _db.accounts,
    )..where((a) => a.deletedAt.isNull())).get();
    checkCurrencyDigits(
      currency: account.currency,
      digits: account.currencyDigits,
      existing: [for (final r in rows) (r.currency, r.currencyDigits)],
    );
  }

  Future<void> _updateRow(String id, AccountsCompanion changes) {
    return (_db.update(
      _db.accounts,
    )..where((a) => a.id.equals(id))).write(changes);
  }

  int _nowMs() => _clock.now().toUtc().millisecondsSinceEpoch;
}
