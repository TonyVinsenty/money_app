import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/csv/csv_codec.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/accounts/data/accounts_repository_impl.dart';
import 'package:money_app/features/accounts/data/transfers_repository_impl.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/transfer.dart';
import 'package:money_app/features/categories/data/categories_repository_impl.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/csv_import/data/csv_import_writer.dart';
import 'package:money_app/features/csv_import/domain/parse_csv_import.dart';
import 'package:money_app/features/csv_import/domain/plan_csv_import.dart';
import 'package:money_app/features/export/domain/transactions_export.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/csv_v1_compat.dart';
import '../../../support/fake_id_generator.dart';
import '../../../support/fixed_clock.dart';
import '../../../support/in_memory_database.dart';

const _food = 'aaaaaaaa-0000-4000-8000-00000000000a';
const _cafe = 'aaaaaaaa-0000-4000-8000-00000000000b';
const _salary = 'aaaaaaaa-0000-4000-8000-00000000000c';
const _old = 'aaaaaaaa-0000-4000-8000-00000000000d';

const _card = 'cccccccc-0000-4000-8000-00000000000a';
const _wallet = 'cccccccc-0000-4000-8000-00000000000b';
const _oldAccount = 'cccccccc-0000-4000-8000-00000000000c';
const _cash = 'cccccccc-0000-4000-8000-0000000000a1';

String _txId(int n) =>
    'bbbbbbbb-0000-4000-8000-${n.toString().padLeft(12, "0")}';

/// База в памяти с репозиториями и писателем импорта.
final class _Env {
  _Env(this.db, this.clock)
    : categories = DriftCategoriesRepository(db, clock: clock),
      accounts = DriftAccountsRepository(db, clock: clock),
      transactions = DriftTransactionsRepository(db, clock: clock),
      transfers = DriftTransfersRepository(db, clock: clock) {
    writer = CsvImportWriter(
      db: db,
      categories: categories,
      accounts: accounts,
      transfers: transfers,
      transactions: transactions,
      ids: FakeIdGenerator(prefix: 'new'),
      isKnownIconKey: (key) => key == 'x',
    );
  }

  final AppDatabase db;
  final FixedClock clock;
  final DriftCategoriesRepository categories;
  final DriftAccountsRepository accounts;
  final DriftTransactionsRepository transactions;
  final DriftTransfersRepository transfers;
  late final CsvImportWriter writer;

  Future<String> export() async => buildTransactionsCsv(
    transactions: await transactions.findAllLive(),
    categories: await categories.watchAll().first,
    accounts: await accounts.watchAll().first,
    transfers: await transfers.findAllLive(),
  );

  Future<int> categoryCount() async =>
      (await categories.watchAll().first).length;

  Future<int> transactionCount() async =>
      (await transactions.findAllLive()).length;

  /// Разбор файла, план и запись; возвращает план.
  Future<CsvImportPlan> import(String csv) async {
    final parsed = parseCsvImport(utf8.encode(csv), clock: clock);
    expect(parsed, isA<CsvImportParsed>());
    parsed as CsvImportParsed;
    expect(parsed.errors, isEmpty);
    final plan = await writer.prepare(
      parsed.rows,
      openingBalances: parsed.openingBalances,
      transfers: parsed.transfers,
    );
    await writer.write(plan);
    return plan;
  }
}

Category _top(String id, CategoryKind kind, String name, int order) =>
    Category.topLevel(
      id: id,
      kind: kind,
      name: name,
      iconKey: 'x',
      sortOrder: order,
    );

Transaction _tx(
  String id, {
  TransactionType type = TransactionType.expense,
  String category = _food,
  String? sub,
  String? note,
  int day = 1,
  String? account,
}) => Transaction(
  id: id,
  type: type,
  amount: Money.fromMinor(12345, 'RUB'),
  occurredOn: DateOnly(2026, 10, day),
  occurredAt: DateTime.utc(2026, 10, day, 9, 30),
  categoryId: category,
  subcategoryId: sub,
  note: note,
  accountId: account,
);

Account _account(
  String id,
  String name,
  int minor, {
  String currency = 'RUB',
  int digits = 2,
  int order = 0,
}) => Account(
  id: id,
  name: name,
  iconKey: 'card',
  openingBalance: Money.fromMinor(minor, currency),
  sortOrder: order,
  currencyDigits: digits,
);

ParsedCsvRow _row({required String category, String? categoryId, String? id}) =>
    ParsedCsvRow(
      line: 2,
      day: DateOnly(2026, 10, 2),
      occurredAt: DateTime.utc(2026, 10, 2, 9),
      type: TransactionType.expense,
      amount: Money.fromMinor(500, 'RUB'),
      categoryName: category,
      subcategoryName: null,
      note: null,
      transactionId: id,
      categoryId: categoryId,
      subcategoryId: null,
    );

void main() {
  late AppDatabase db;
  late _Env env;

  setUp(() async {
    db = await openInMemoryDatabase();
    env = _Env(db, FixedClock(DateTime.utc(2026, 10, 7, 12)));
  });

  tearDown(() => db.close());

  Future<void> seedSource() async {
    final food = _top(_food, CategoryKind.expense, 'Еда', 0);
    await env.categories.create(food);
    await env.categories.create(
      Category.subcategoryOf(
        id: _cafe,
        parent: food,
        name: 'Кафе',
        iconKey: 'x',
        sortOrder: 0,
      ),
    );
    await env.categories.create(
      _top(_salary, CategoryKind.income, 'Зарплата', 0),
    );
    await env.categories.create(_top(_old, CategoryKind.expense, 'Старое', 1));
    // Счета: рублёвый с долгом, своя валюта с 4 знаками, архивный без операций.
    await env.accounts.create(_account(_card, 'Карта', -150000));
    await env.accounts.create(
      _account(_wallet, 'Кошелёк', 15, currency: 'XYZ', digits: 4, order: 1),
    );
    await env.accounts.create(_account(_oldAccount, 'Старый', 0, order: 2));
    await env.accounts.archive(_oldAccount);
    await env.transactions.add(
      _tx(_txId(1), sub: _cafe, note: 'a;b "q"\nline2', account: _card),
    );
    await env.transactions.add(
      _tx(_txId(2), type: TransactionType.income, category: _salary, day: 3),
    );
    await env.transactions.add(_tx(_txId(3), category: _old, day: 5));
    await env.categories.archive(_old);
  }

  test('экспорт -> импорт в пустую базу -> экспорт: тот же файл', () async {
    await seedSource();
    final first = await env.export();

    final other = await openInMemoryDatabase();
    addTearDown(other.close);
    final target = _Env(other, env.clock);
    final plan = await target.import(first);

    expect(plan.categoriesToCreate, hasLength(4));
    expect(plan.accountsToCreate, hasLength(3));
    // Счета, остатки (в том числе долг и 4 знака), моменты создания и значки
    // категорий возвращаются: файл совпадает побайтно.
    final second = await target.export();
    expect(utf8.encode(second), utf8.encode(first));
    expect(first, contains('Начальный остаток'));
    expect(
      decodeCsv(first).skip(1).map((r) => r[csvV2IconColumn]),
      contains('x'),
    );
    final restored = await target.accounts.watchAll().first;
    expect(restored.map((a) => a.currencyDigits), contains(4));
  });

  Transfer transfer(
    String n,
    String from,
    String to,
    int minor,
    String currency, {
    int day = 4,
    String? note,
  }) => Transfer(
    id: 'dddddddd-0000-4000-8000-${n.padLeft(12, "0")}',
    fromAccountId: from,
    toAccountId: to,
    amount: Money.fromMinor(minor, currency),
    occurredOn: DateOnly(2026, 10, day),
    occurredAt: DateTime.utc(2026, 10, day, 10),
    note: note,
  );

  /// Счета (в том числе архивный, BTC и своя валюта) и переводы между ними.
  Future<void> seedTransfers() async {
    await seedSource();
    const btc1 = 'cccccccc-0000-4000-8000-0000000000b1';
    const btc2 = 'cccccccc-0000-4000-8000-0000000000b2';
    const own2 = 'cccccccc-0000-4000-8000-0000000000e2';
    await env.accounts.create(
      _account(btc1, 'Кошелёк BTC', 200000, currency: 'BTC', digits: 8),
    );
    await env.accounts.create(
      _account(btc2, 'Биржа BTC', 0, currency: 'BTC', digits: 8, order: 4),
    );
    await env.accounts.create(
      _account(own2, 'Кошелёк 2', 5, currency: 'XYZ', digits: 4, order: 5),
    );
    await env.accounts.create(_account(_cash, 'Наличные', 1000, order: 3));
    await env.transfers.add(
      transfer('1', _card, _cash, 150000, 'RUB', note: 'a;b "q"'),
    );
    await env.transfers.add(transfer('2', btc1, btc2, 150000, 'BTC', day: 5));
    await env.transfers.add(transfer('3', _wallet, own2, 12345, 'XYZ'));
    // Перевод со счёта, который потом уходит в архив.
    const piggy = 'cccccccc-0000-4000-8000-0000000000f1';
    await env.accounts.create(_account(piggy, 'Копилка', 0, order: 6));
    await env.transfers.add(transfer('4', _cash, piggy, 100, 'RUB'));
    await env.accounts.archive(piggy);
  }

  test('переводы: экспорт -> импорт в пустую базу -> экспорт тот же файл, '
      'остатки равны', () async {
    await seedTransfers();
    final first = await env.export();
    final balances = await env.accounts.watchBalances().first;
    expect(first, contains('Перевод'));

    final other = await openInMemoryDatabase();
    addTearDown(other.close);
    final target = _Env(other, env.clock);
    final plan = await target.import(first);

    expect(plan.transfers, hasLength(4));
    expect(utf8.encode(await target.export()), utf8.encode(first));
    expect(await target.accounts.watchBalances().first, balances);

    // Повторный импорт: переводы уже есть, ничего не добавляется.
    final again = await target.import(first);
    expect(again.transfers, isEmpty);
    expect(again.transactions, isEmpty);
    expect(again.accountsToCreate, isEmpty);
    expect(await target.export(), first);
  });

  test('перевод без ID: отпечаток, повторный импорт не задваивает', () async {
    const csv =
        'Дата;Тип;Сумма;Валюта;Категория;Подкатегория;Комментарий;Счёт;'
        'Счёт зачисления\r\n'
        '02.10.2026;Начальный остаток;100;;;;;Карта;\r\n'
        '02.10.2026;Начальный остаток;0;;;;;Наличные;\r\n'
        '03.10.2026;Перевод;5;;;;;Карта;Наличные\r\n'
        '03.10.2026;Перевод;5;;;;;Карта;Наличные\r\n';
    final first = await env.import(csv);
    expect(first.transfers, hasLength(2));
    expect(first.transfers.first.id, isNot(first.transfers.last.id));

    final again = await env.import(csv);
    expect(again.transfers, isEmpty);
    expect(again.skippedExisting, 4);
  });

  test('удалённый в приложении перевод пропускается как удалённый', () async {
    await seedTransfers();
    final csv = await env.export();
    final id = (await env.transfers.findAllLive()).first.id;
    await env.transfers.softDelete(id);

    final again = await env.import(csv);

    expect(again.transfers, isEmpty);
    expect(again.skippedDeleted, 1);
  });

  test('сбой записи перевода откатывает счета, категории и операции', () async {
    final plan = CsvImportPlan(
      transactions: [_tx(_txId(1))],
      skippedExisting: 0,
      skippedDeleted: 0,
      categoriesToCreate: [_top(_food, CategoryKind.expense, 'Еда', 0)],
      accountsToCreate: [
        _account(_card, 'Карта', 100),
        _account(_wallet, 'Кошелёк', 0, order: 1),
      ],
      transfers: [transfer('1', _card, 'missing', 100, 'RUB')],
      errors: const [],
    );

    await expectLater(env.writer.write(plan), throwsArgumentError);

    expect(await env.categoryCount(), 0);
    expect(await env.transactionCount(), 0);
    expect(await env.accounts.findById(_card), isNull);
  });

  test('импорт: значок известен - берётся, незнакомый - «Другое»', () async {
    final csv = encodeCsv([
      transactionsExportHeaders,
      [
        ...['02.10.2026', 'Расход', '5,00', 'RUB', 'Спорт', 'Зал'],
        ...[
          '',
          '',
          '',
          '',
          '',
          '',
        ], // комментарий, счета, ID операции и категорий
        '2026-10-02T09:00:00.000Z',
        ...['', ''], // ID счетов
        ...['x', 'zzz'], // значки категории и подкатегории
      ],
    ]);

    await env.import(csv);

    final icons = {
      for (final c in await env.categories.watchAll().first) c.name: c.iconKey,
    };
    expect(icons, {'Спорт': 'x', 'Зал': 'more_horiz'});
  });

  test('повторный импорт ничего не меняет', () async {
    await seedSource();
    final csv = await env.export();
    final other = await openInMemoryDatabase();
    addTearDown(other.close);
    final target = _Env(other, env.clock);
    await target.import(csv);
    final afterFirst = await target.export();

    final again = await target.import(csv);

    expect(again.transactions, isEmpty);
    expect(again.categoriesToCreate, isEmpty);
    // 3 операции и 3 начальных остатка счетов (5.18b, П6).
    expect(again.skippedExisting, 6);
    expect(await target.categoryCount(), 4);
    expect(await target.transactionCount(), 3);
    expect(await target.export(), afterFirst);
  });

  test('сбой на середине записи: база не изменилась', () async {
    final plan = CsvImportPlan(
      transactions: [
        _tx(_txId(1)),
        _tx(_txId(2), category: 'missing'),
      ],
      skippedExisting: 0,
      skippedDeleted: 0,
      categoriesToCreate: [_top(_food, CategoryKind.expense, 'Еда', 0)],
      errors: const [],
    );

    await expectLater(env.writer.write(plan), throwsArgumentError);

    expect(await env.categoryCount(), 0);
    expect(await env.transactionCount(), 0);
  });

  test('счета и операции пишутся вместе; сбой откатывает и счета', () async {
    final good = CsvImportPlan(
      transactions: [_tx(_txId(1), account: _card)],
      skippedExisting: 0,
      skippedDeleted: 0,
      categoriesToCreate: [_top(_food, CategoryKind.expense, 'Еда', 0)],
      accountsToCreate: [_account(_card, 'Карта', 100)],
      errors: const [],
    );
    await env.writer.write(good);
    expect((await env.transactions.findById(_txId(1)))?.accountId, _card);
    expect(await env.accounts.findById(_card), isNotNull);

    final bad = CsvImportPlan(
      transactions: [_tx(_txId(2), category: 'missing')],
      skippedExisting: 0,
      skippedDeleted: 0,
      categoriesToCreate: const [],
      accountsToCreate: [_account(_wallet, 'Кошелёк', 0)],
      errors: const [],
    );
    await expectLater(env.writer.write(bad), throwsArgumentError);
    expect(await env.accounts.findById(_wallet), isNull);
  });

  test('id операции уже есть при записи: ошибка и откат', () async {
    await env.categories.create(_top(_food, CategoryKind.expense, 'Еда', 0));
    await env.transactions.add(_tx(_txId(1)));
    final plan = CsvImportPlan(
      transactions: [_tx(_txId(2)), _tx(_txId(1))],
      skippedExisting: 0,
      skippedDeleted: 0,
      categoriesToCreate: [_top(_salary, CategoryKind.income, 'Зарплата', 0)],
      errors: const [],
    );

    await expectLater(env.writer.write(plan), throwsA(isA<Object>()));

    expect(await env.categoryCount(), 1);
    expect(await env.transactionCount(), 1);
  });

  test('пустой план ничего не делает', () async {
    final plan = await env.writer.prepare(const []);
    await env.writer.write(plan);
    expect(await env.categoryCount(), 0);
  });

  test('операция по id идёт в архивную категорию, она остаётся '
      'архивной', () async {
    await env.categories.create(_top(_food, CategoryKind.expense, 'Еда', 0));
    await env.categories.archive(_food);

    final plan = await env.writer.prepare([
      _row(category: 'Еда', categoryId: _food, id: _txId(9)),
    ]);
    await env.writer.write(plan);

    final saved = await env.transactions.findById(_txId(9));
    expect(saved?.categoryId, _food);
    expect((await env.categories.findById(_food))?.isArchived, isTrue);
  });

  test('обычное добавление в архивную категорию запрещено', () async {
    await env.categories.create(_top(_food, CategoryKind.expense, 'Еда', 0));
    await env.categories.archive(_food);

    await expectLater(
      env.transactions.add(_tx(_txId(1))),
      throwsA(
        isA<TransactionRuleException>().having(
          (e) => e.rule,
          'rule',
          TransactionRule.categoryArchived,
        ),
      ),
    );
  });

  test('id совпал с мягко удалённой категорией: новый id', () async {
    await env.categories.create(_top(_food, CategoryKind.expense, 'Еда', 0));
    await (db.update(db.categories)..where((c) => c.id.equals(_food))).write(
      const CategoriesCompanion(deletedAt: Value(1)),
    );

    final plan = await env.writer.prepare([
      _row(category: 'Еда', categoryId: _food),
    ]);
    await env.writer.write(plan);

    expect(plan.categoriesToCreate.single.id, 'new-1');
    expect((await env.categories.findById('new-1'))?.name, 'Еда');
    expect(await env.categories.findById(_food), isNull);
  });
}
