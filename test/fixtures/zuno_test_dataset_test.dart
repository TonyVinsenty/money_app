import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/csv/csv_codec.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/accounts/data/accounts_repository_impl.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/categories/data/categories_repository_impl.dart';
import 'package:money_app/features/categories/data/default_categories_seeder.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/csv_import/data/csv_import_writer.dart';
import 'package:money_app/features/csv_import/domain/parse_csv_import.dart';
import 'package:money_app/features/csv_import/domain/plan_csv_import.dart';
import 'package:money_app/features/export/domain/transactions_export.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../tool/make_test_dataset.dart';
import '../support/csv_v1_compat.dart';
import '../support/fake_id_generator.dart';
import '../support/fixed_clock.dart';
import '../support/in_memory_database.dart';

/// Итоги набора в копейках. Посчитаны по тексту файла отдельно от кода
/// приложения; если набор перегенерируют с другим зерном, их нужно
/// пересчитать.
const _rows = 295;
const _julyIncomeMinor = 12747499; // 127 474,99 (7 операций)
const _julyExpensesMinor = 15295252; // 152 952,52 (146 операций)
const _septemberIncomeMinor = 11528531; // 115 285,31 (5 операций)
const _septemberExpensesMinor = 12531282; // 125 312,82 (137 операций)
const _hobbyRows = 8; // все в июле

/// Подкатегории, которых нет в стандартном наборе категорий.
const _newSubcategories = {
  'Овощи',
  'Молочное',
  'Хлеб',
  'Кофе',
  'Обед',
  'Метро',
  'Такси',
  'Коммуналка',
  'Кино',
  'Аванс',
  'Расчёт',
};

/// База в памяти с репозиториями и писателем импорта.
final class _Env {
  _Env(this.db, this.clock)
    : categories = DriftCategoriesRepository(db, clock: clock),
      transactions = DriftTransactionsRepository(db, clock: clock) {
    writer = CsvImportWriter(
      db: db,
      categories: categories,
      transactions: transactions,
      ids: FakeIdGenerator(prefix: 'new'),
    );
  }

  final AppDatabase db;
  final FixedClock clock;
  final DriftCategoriesRepository categories;
  final DriftTransactionsRepository transactions;
  late final CsvImportWriter writer;

  Future<CsvImportPlan> prepare() async {
    final bytes = File(testDatasetPath).readAsBytesSync();
    final parsed = parseCsvImport(bytes, clock: clock);
    expect(parsed, isA<CsvImportParsed>());
    parsed as CsvImportParsed;
    expect(parsed.errors, isEmpty);
    return writer.prepare(parsed.rows);
  }

  Future<int> total(TransactionType type, int month) async {
    final money = await transactions
        .watchTotal(type: type, period: monthRange(DateOnly(2026, month, 1)))
        .first;
    return money.minorUnits;
  }
}

void main() {
  late AppDatabase db;
  late _Env env;

  setUp(() async {
    db = await openInMemoryDatabase();
    // Сегодня в тесте — 7 октября 2026: все даты набора в прошлом.
    env = _Env(db, FixedClock(DateTime.utc(2026, 10, 7, 12)));
  });

  tearDown(() => db.close());

  test('файл в репозитории совпадает с выводом скрипта', () {
    expect(
      File(testDatasetPath).readAsBytesSync(),
      utf8.encode(buildTestDataset()),
    );
  });

  group(
    'набор в приложении со стандартными категориями и архивным «Хобби»',
    () {
      setUp(() async {
        await DefaultCategoriesSeeder(
          db,
          idGenerator: FakeIdGenerator(prefix: 'seed'),
          clock: env.clock,
        ).seed();
        final hobby = Category.topLevel(
          id: testDatasetHobbyId,
          kind: CategoryKind.expense,
          name: 'Хобби',
          iconKey: 'palette',
          sortOrder: 10,
        );
        await env.categories.create(hobby);
        for (final (id, name) in [
          (testDatasetHobbyPaintsId, 'Краски'),
          (testDatasetHobbyBrushesId, 'Кисти'),
        ]) {
          await env.categories.create(
            Category.subcategoryOf(
              id: id,
              parent: hobby,
              name: name,
              iconKey: 'palette',
              sortOrder: 0,
            ),
          );
        }
        await env.categories.archive(testDatasetHobbyId);
      });

      test('загружается без ошибок, создаются только подкатегории', () async {
        final plan = await env.prepare();
        expect(plan.errors, isEmpty);
        expect(plan.transactions, hasLength(_rows));
        expect(plan.skippedExisting, 0);
        expect(plan.skippedDeleted, 0);
        expect(
          plan.categoriesToCreate.map((c) => c.name).toSet(),
          _newSubcategories,
        );
        expect(
          plan.categoriesToCreate.every((c) => c.parentId != null),
          isTrue,
        );
      });

      test('итоги месяцев совпадают, август пустой', () async {
        await env.writer.write(await env.prepare());

        expect(await env.total(TransactionType.income, 7), _julyIncomeMinor);
        expect(await env.total(TransactionType.expense, 7), _julyExpensesMinor);
        expect(await env.total(TransactionType.income, 8), 0);
        expect(await env.total(TransactionType.expense, 8), 0);
        expect(
          await env.total(TransactionType.income, 9),
          _septemberIncomeMinor,
        );
        expect(
          await env.total(TransactionType.expense, 9),
          _septemberExpensesMinor,
        );
        expect(await env.transactions.findAllLive(), hasLength(_rows));
      });

      test('все операции на одном счёте со стартом 0: остаток = доходы минус '
          'расходы набора', () async {
        await env.writer.write(await env.prepare());
        final accounts = DriftAccountsRepository(db, clock: env.clock);
        await accounts.create(
          Account(
            id: 'acc-all',
            name: 'Всё',
            iconKey: 'card',
            openingBalance: Money.zero('RUB'),
            sortOrder: 0,
            currencyDigits: 2,
          ),
        );
        await db.customStatement(
          "UPDATE transactions SET account_id = 'acc-all'",
        );

        final balances = await accounts.watchBalances().first;
        expect(
          balances['acc-all']!.minorUnits,
          _julyIncomeMinor +
              _septemberIncomeMinor -
              _julyExpensesMinor -
              _septemberExpensesMinor,
        );
      });

      test('операции «Хобби» попали в архивную категорию', () async {
        await env.writer.write(await env.prepare());

        final hobby = await env.categories.findById(testDatasetHobbyId);
        expect(hobby!.isArchived, isTrue);
        final inHobby = (await env.transactions.findAllLive())
            .where((t) => t.categoryId == testDatasetHobbyId)
            .toList();
        expect(inHobby, hasLength(_hobbyRows));
        expect(inHobby.every((t) => t.occurredOn.month == 7), isTrue);
      });

      test('повторная загрузка ничего не добавляет', () async {
        await env.writer.write(await env.prepare());

        final again = await env.prepare();
        expect(again.transactions, isEmpty);
        expect(again.categoriesToCreate, isEmpty);
        expect(again.skippedExisting, _rows);
      });
    },
  );

  test('импорт в пустую базу и экспорт дают тот же файл', () async {
    await env.writer.write(await env.prepare());

    final exported = buildTransactionsCsv(
      transactions: await env.transactions.findAllLive(),
      categories: await env.categories.watchAll().first,
      accounts: const [],
    );
    // v1-файл читается без счетов: экспорт v2 без колонок значков равен ему
    // с вставленными пустыми колонками счёта (ADR 0010, п. 10 и 17).
    final v1 = File(testDatasetPath).readAsStringSync();
    expect(
      utf8.encode(stripIconColumns(exported)),
      utf8.encode(v1AsV2WithoutIcons(v1)),
    );
    // Колонки значков проверяются отдельно: ключ равен значку в базе.
    final categories = {
      for (final c in await env.categories.watchAll().first) c.id: c,
    };
    final transactions = await env.transactions.findAllLive();
    final byId = {for (final t in transactions) t.id: t};
    final body = decodeCsv(exported).skip(1).toList();
    expect(body, hasLength(transactions.length));
    for (final row in body) {
      final t = byId[row[9]]!;
      expect(row[csvV2IconColumn], categories[t.categoryId]!.iconKey);
      expect(
        row[csvV2SubcategoryIconColumn],
        t.subcategoryId == null ? '' : categories[t.subcategoryId]!.iconKey,
      );
    }
    expect(iconColumns(exported), hasLength(transactions.length));
  });
}
