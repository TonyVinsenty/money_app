import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/accounts/data/accounts_repository_impl.dart';
import 'package:money_app/features/accounts/data/transfers_repository_impl.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/account_balances.dart';
import 'package:money_app/features/accounts/domain/balance_journal.dart';
import 'package:money_app/features/accounts/domain/transfer.dart';
import 'package:money_app/features/categories/data/categories_repository_impl.dart';
import 'package:money_app/features/export/domain/transactions_export.dart';
import 'package:money_app/features/recurring/data/recurring_repository_impl.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/fixed_clock.dart';
import '../../../support/in_memory_database.dart';

/// Удаление архивного счёта (ADR 0010, п. 19; шаг 7.30g).
void main() {
  late AppDatabase db;
  late FixedClock clock;
  late DriftAccountsRepository accounts;
  late DriftTransfersRepository transfers;
  late DriftTransactionsRepository transactions;
  late DriftRecurringRepository recurring;
  late DriftCategoriesRepository categories;

  Future<void> addAccount(String id, {int opening = 0, bool archive = false}) {
    return accounts.create(
      Account(
        id: id,
        name: 'Account $id',
        iconKey: 'card',
        openingBalance: Money.fromMinor(opening, 'RUB'),
        sortOrder: 0,
        currencyDigits: 2,
        archivedAt: archive ? DateTime.utc(2026, 9, 1) : null,
      ),
    );
  }

  Future<void> addOperation(String id, String? accountId, {int minor = 100}) {
    return transactions.add(
      Transaction(
        id: id,
        type: TransactionType.expense,
        amount: Money.fromMinor(minor, 'RUB'),
        occurredOn: DateOnly(2026, 8, 1),
        occurredAt: DateTime.utc(2026, 8, 1, 9),
        categoryId: 'cat-e',
        accountId: accountId,
      ),
    );
  }

  Future<void> addTransfer(String id, String from, String to) {
    return transfers.add(
      Transfer(
        id: id,
        fromAccountId: from,
        toAccountId: to,
        amount: Money.fromMinor(300, 'RUB'),
        occurredOn: DateOnly(2026, 8, 2),
        occurredAt: DateTime.utc(2026, 8, 2, 9),
      ),
    );
  }

  /// Регулярный платёж прямой записью: форма платежа здесь не нужна.
  Future<void> addPayment(String id, String? accountId) {
    return db.customStatement(
      'INSERT INTO recurring_payments (id, title, type, amount_minor, '
      'currency, category_id, account_id, unit, every, starts_on, remind, '
      'created_at, updated_at) '
      "VALUES (?, 'Rent', 'expense', 1000, 'RUB', 'cat-e', ?, 'month', 1, "
      '20260801, 0, 1, 1)',
      [id, accountId],
    );
  }

  Future<String?> accountOf(String table, String id) async {
    final row = await db
        .customSelect(
          'SELECT account_id FROM $table WHERE id = ?',
          variables: [Variable<String>(id)],
        )
        .getSingle();
    return row.read<String?>('account_id');
  }

  setUp(() async {
    db = await openInMemoryDatabase();
    clock = FixedClock(DateTime.utc(2026, 10, 12, 12));
    accounts = DriftAccountsRepository(db, clock: clock);
    transfers = DriftTransfersRepository(db, clock: clock);
    transactions = DriftTransactionsRepository(db, clock: clock);
    recurring = DriftRecurringRepository(db, transactions, clock: clock);
    categories = DriftCategoriesRepository(db, clock: clock);
    await db.customStatement(
      'INSERT INTO categories (id, kind, name, icon_key, parent_id, '
      'sort_order, created_at, updated_at) '
      "VALUES ('cat-e', 'expense', 'E', 'i', NULL, 0, 1, 1)",
    );
    await addAccount('card', opening: 10000);
    await addAccount('test', opening: 5000);
    await addAccount('card2');
    await addOperation('op-test-1', 'test');
    await addOperation('op-test-2', 'test');
    await addOperation('op-card', 'card');
    await addOperation('op-none', null);
    await addTransfer('tr-out', 'test', 'card');
    await addTransfer('tr-in', 'card', 'test');
    await addTransfer('tr-other', 'card', 'card2');
    await addPayment('pay-test', 'test');
    await addPayment('pay-card', 'card');
    await accounts.archive('test');
  });

  tearDown(() => db.close());

  group('linkedCounts', () {
    test('считает живые операции и переводы с обеих сторон', () async {
      final links = await accounts.linkedCounts('test');
      expect(links.transactions, 2);
      expect(links.transfers, 2);
    });

    test('удалённая операция и удалённый перевод не считаются', () async {
      await transactions.softDelete('op-test-1');
      await transfers.softDelete('tr-out');
      final links = await accounts.linkedCounts('test');
      expect(links, (transactions: 1, transfers: 1));
    });

    test('пустой счёт — нули; нет счёта — ArgumentError', () async {
      await addAccount('empty');
      expect(await accounts.linkedCounts('empty'), (
        transactions: 0,
        transfers: 0,
      ));
      expect(() => accounts.linkedCounts('nope'), throwsArgumentError);
    });
  });

  group('deleteArchived', () {
    test('операции на месте, но без счёта; чужие не тронуты', () async {
      await accounts.deleteArchived('test');

      final live = {
        for (final t in await transactions.findAllLive()) t.id: t.accountId,
      };
      expect(live, {
        'op-test-1': null,
        'op-test-2': null,
        'op-card': 'card',
        'op-none': null,
      });
    });

    test('удалённая раньше операция тоже отвязана', () async {
      await transactions.softDelete('op-test-1');
      await accounts.deleteArchived('test');
      expect(await accountOf('transactions', 'op-test-1'), isNull);
    });

    test('регулярный платёж остаётся без счёта', () async {
      await accounts.deleteArchived('test');
      expect(await accountOf('recurring_payments', 'pay-test'), isNull);
      expect(await accountOf('recurring_payments', 'pay-card'), 'card');
      final items = await recurring.watchAll().first;
      expect(
        {for (final item in items) item.payment.id: item.payment.accountId},
        {'pay-test': null, 'pay-card': 'card'},
      );
    });

    test('переводы со счётом не видны, остальные на месте', () async {
      await accounts.deleteArchived('test');
      final live = await transfers.findAllLive();
      expect([for (final t in live) t.id], ['tr-other']);
      expect(await transfers.watchForAccount('card').first, hasLength(1));
    });

    test('счёт пропал из списка, остатков и «Всего»', () async {
      final before = await accounts.watchBalances().first;
      expect(before.keys, containsAll(['card', 'test']));

      await accounts.deleteArchived('test');

      final all = await accounts.watchAll().first;
      expect([for (final a in all) a.id], ['card', 'card2']);
      expect(await accounts.findById('test'), isNull);
      final balances = await accounts.watchBalances().first;
      expect(balances.keys, isNot(contains('test')));
      // Переводы с «test» удалены: у «card» остаётся старт минус её операция
      // и перевод на «card2» (300); «Всего» — ещё плюс 300 на «card2».
      expect(balances['card'], Money.fromMinor(10000 - 100 - 300, 'RUB'));
      expect(
        totalOnAccounts(all, balances, currency: 'RUB'),
        Money.fromMinor(10000 - 100 - 300 + 300, 'RUB'),
      );
    });

    test('выбор счёта и «История счетов» без удалённого счёта', () async {
      await accounts.deleteArchived('test');
      final all = await accounts.watchAll().first;
      // Выбор счёта в формах строится из живых не архивных счетов.
      expect([for (final a in all) a.id], isNot(contains('test')));
      final journal = buildBalanceJournal(all, await transfers.findAllLive());
      for (final entry in journal) {
        switch (entry) {
          case AccountCreatedEntry(:final account):
          case AccountArchivedEntry(:final account):
            expect(account.id, isNot('test'));
          case TransferEntry(:final transfer):
            expect(transfer.id, 'tr-other');
        }
      }
    });

    test('CSV: удалённого счёта нет, его операции — без счёта', () async {
      await accounts.deleteArchived('test');
      final rows = buildTransactionsCsvRows(
        transactions: await transactions.findAllLive(),
        categories: await categories.watchAll().first,
        accounts: await accounts.watchAll().first,
        transfers: await transfers.findAllLive(),
        recurring: [
          for (final item in await recurring.watchAll().first) item.payment,
        ],
      );
      final text = rows.map((r) => r.join(';')).join('\n');
      expect(text, isNot(contains('Account test')));
      expect(text, contains('Account card'));
    });

    test('счёт не в архиве — отказ, ничего не меняется', () async {
      expect(() => accounts.deleteArchived('card'), throwsStateError);
      await Future<void>.delayed(Duration.zero);
      expect(await accounts.findById('card'), isNotNull);
      expect(await accountOf('transactions', 'op-card'), 'card');
    });

    test('удалённый и несуществующий — ArgumentError', () async {
      await accounts.deleteArchived('test');
      expect(() => accounts.deleteArchived('test'), throwsArgumentError);
      expect(() => accounts.deleteArchived('nope'), throwsArgumentError);
    });

    test('после удаления имя свободно: можно завести счёт заново', () async {
      await accounts.deleteArchived('test');
      await addAccount('test2');
      await accounts.update('test2', name: 'Account test', iconKey: 'card');
      expect((await accounts.findById('test2'))?.name, 'Account test');
    });
  });
}
