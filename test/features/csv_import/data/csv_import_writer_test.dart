import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/csv/csv_codec.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/accounts/data/accounts_repository_impl.dart';
import 'package:money_app/features/accounts/domain/account.dart';
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

String _txId(int n) =>
    'bbbbbbbb-0000-4000-8000-${n.toString().padLeft(12, "0")}';

/// База в памяти с репозиториями и писателем импорта.
final class _Env {
  _Env(this.db, this.clock)
    : categories = DriftCategoriesRepository(db, clock: clock),
      accounts = DriftAccountsRepository(db, clock: clock),
      transactions = DriftTransactionsRepository(db, clock: clock) {
    writer = CsvImportWriter(
      db: db,
      categories: categories,
      accounts: accounts,
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
  late final CsvImportWriter writer;

  Future<String> export() async => buildTransactionsCsv(
    transactions: await transactions.findAllLive(),
    categories: await categories.watchAll().first,
    accounts: await accounts.watchAll().first,
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
    expect(again.skippedExisting, 3);
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
