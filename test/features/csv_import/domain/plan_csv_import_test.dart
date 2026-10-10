import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/money/parse_amount.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/account_icons.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/csv_import/domain/csv_import_failures.dart';
import 'package:money_app/features/csv_import/domain/parse_csv_import.dart';
import 'package:money_app/features/csv_import/domain/plan_csv_import.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

final class _SeqIds implements IdGenerator {
  var _n = 0;

  @override
  String newId() => 'new-${++_n}';
}

const _food = 'cat-food';
const _salary = 'cat-salary';
const _sub = 'sub-cafe';

Category _top(
  String id,
  CategoryKind kind,
  String name, {
  bool archived = false,
}) {
  final c = Category.topLevel(
    id: id,
    kind: kind,
    name: name,
    iconKey: 'x',
    sortOrder: 3,
  );
  return archived ? c.archived(DateTime.utc(2026, 1, 1)) : c;
}

Category _child(String id, Category parent, String name) =>
    Category.subcategoryOf(
      id: id,
      parent: parent,
      name: name,
      iconKey: 'x',
      sortOrder: 0,
    );

ParsedCsvRow _row({
  int line = 2,
  TransactionType type = TransactionType.expense,
  int amount = 10000,
  String category = 'Еда',
  String? sub,
  String? note,
  String? id,
  String? categoryId,
  String? subcategoryId,
}) {
  return ParsedCsvRow(
    line: line,
    day: DateOnly(2026, 10, 1),
    occurredAt: DateTime.utc(2026, 10, 1, 9),
    type: type,
    amount: Money.fromMinor(amount, 'RUB'),
    categoryName: category,
    subcategoryName: sub,
    note: note,
    transactionId: id,
    categoryId: categoryId,
    subcategoryId: subcategoryId,
  );
}

CsvImportPlan _plan(
  List<ParsedCsvRow> rows, {
  List<Category>? categories,
  Set<String> live = const {},
  Set<String> deleted = const {},
  List<ParsedOpeningBalance> balances = const [],
  List<Account> accounts = const [],
  Set<String> deletedAccounts = const {},
}) {
  return planCsvImport(
    rows: rows,
    categories: categories ?? [_top(_food, CategoryKind.expense, 'Еда')],
    liveTransactionIds: live,
    deletedTransactionIds: deleted,
    ids: _SeqIds(),
    isKnownIconKey: (key) => key == 'star' || key == 'cart',
    today: DateOnly(2026, 10, 7),
    openingBalances: balances,
    accounts: accounts,
    deletedAccountIds: deletedAccounts,
  );
}

ParsedOpeningBalance _ob(
  String name, {
  int line = 2,
  int minor = 1200000,
  String currency = 'RUB',
  String? id,
  int? customDigits,
}) => ParsedOpeningBalance(
  line: line,
  day: DateOnly(2026, 9, 1),
  occurredAt: DateTime.utc(2026, 9, 1, 8),
  accountName: name,
  accountId: id,
  amount: Money.fromMinor(minor, currency),
  customDigits: customDigits,
);

Account _account(
  String id,
  String name, {
  String currency = 'RUB',
  int digits = 2,
  int sort = 0,
  bool archived = false,
}) {
  final a = Account(
    id: id,
    name: name,
    iconKey: 'other',
    openingBalance: Money.fromMinor(0, currency),
    sortOrder: sort,
    currencyDigits: digits,
  );
  return archived ? a.archived(DateTime.utc(2026, 1, 1)) : a;
}

ParsedCsvRow _accRow({
  String? account,
  String? accountId,
  String currency = 'RUB',
  String? categoryIcon,
  String? subIcon,
  String category = 'Еда',
  String? sub,
}) => ParsedCsvRow(
  line: 7,
  day: DateOnly(2026, 10, 1),
  occurredAt: DateTime.utc(2026, 10, 1, 9),
  type: TransactionType.expense,
  amount: Money.fromMinor(500, currency),
  categoryName: category,
  subcategoryName: sub,
  note: null,
  transactionId: null,
  categoryId: null,
  subcategoryId: null,
  accountName: account,
  accountId: accountId,
  categoryIconKey: categoryIcon,
  subcategoryIconKey: subIcon,
);

void main() {
  test('id из файла совпал с id мягко удалённой категории: id новый', () {
    final plan = planCsvImport(
      rows: [_row(category: 'Кафе', categoryId: 'gone-1')],
      categories: [_top(_food, CategoryKind.expense, 'Еда')],
      liveTransactionIds: const {},
      deletedTransactionIds: const {},
      deletedCategoryIds: const {'GONE-1'},
      ids: _SeqIds(),
      isKnownIconKey: (_) => true,
      today: DateOnly(2026, 10, 7),
    );
    expect(plan.categoriesToCreate.single.id, 'new-1');
    expect(plan.transactions.single.categoryId, 'new-1');
  });

  test('новые строки добавляются в существующую категорию по имени', () {
    final plan = _plan([_row(category: ' еда ')]);
    expect(plan.transactions.single.categoryId, _food);
    expect(plan.categoriesToCreate, isEmpty);
    expect(plan.errors, isEmpty);
  });

  test('повторный импорт: строки с ID и без ID не добавляются снова', () {
    final rows = [
      _row(id: 'AAAAAAAA-0000-4000-8000-000000000001'),
      _row(amount: 500, note: 'без id'),
      _row(amount: 500, note: 'без id'),
    ];
    final first = _plan(rows);
    expect(first.transactions, hasLength(3));
    final second = _plan(
      rows,
      live: {for (final t in first.transactions) t.id},
    );
    expect(second.transactions, isEmpty);
    expect(second.skippedExisting, 3);
  });

  test('две одинаковые покупки в день остаются двумя разными id', () {
    final plan = _plan([_row(amount: 700), _row(amount: 700)]);
    expect(plan.transactions, hasLength(2));
    expect(plan.transactions[0].id, isNot(plan.transactions[1].id));
  });

  test('отпечаток не зависит от регистра и пробелов в имени категории', () {
    final a = _plan([_row(category: 'Еда')]).transactions.single.id;
    final b = _plan([_row(category: '  ЕДА ')]).transactions.single.id;
    expect(a, b);
  });

  test('удалённая в приложении операция пропускается отдельным счётчиком', () {
    final plan = _plan(
      [_row(id: '0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeee1')],
      deleted: {'0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeee1'},
    );
    expect(plan.transactions, isEmpty);
    expect(plan.skippedDeleted, 1);
    expect(plan.skippedExisting, 0);
  });

  test('одноимённые категории дохода и расхода разные', () {
    final plan = _plan([
      _row(category: 'Прочее'),
      _row(type: TransactionType.income, category: 'Прочее'),
    ]);
    expect(plan.categoriesToCreate.map((c) => c.kind), [
      CategoryKind.expense,
      CategoryKind.income,
    ]);
    expect(
      plan.transactions[0].categoryId,
      isNot(plan.transactions[1].categoryId),
    );
  });

  test('одна новая категория в многих строках создаётся один раз', () {
    final plan = _plan([
      _row(category: 'Спорт', sub: 'Зал'),
      _row(category: 'спорт', sub: 'зал', amount: 5),
    ]);
    expect(plan.categoriesToCreate.map((c) => c.name), ['Спорт', 'Зал']);
    expect(plan.categoriesToCreate[1].parentId, plan.categoriesToCreate[0].id);
    expect(plan.transactions[1].subcategoryId, plan.categoriesToCreate[1].id);
  });

  test('категория создаётся с id из файла, если он свободен', () {
    const fileId = 'AAAAAAAA-0000-4000-8000-0000000000AA';
    final plan = _plan([_row(category: 'Спорт', categoryId: fileId)]);
    expect(plan.categoriesToCreate.single.id, fileId.toLowerCase());
    expect(plan.transactions.single.categoryId, fileId.toLowerCase());
  });

  test('id из файла занят - категория получает новый id', () {
    final plan = _plan(
      [_row(category: 'Спорт', categoryId: 'unknown-but-taken')],
      categories: [_top(_food, CategoryKind.expense, 'Еда')],
    );
    // Свободный id берётся из файла...
    expect(plan.categoriesToCreate.single.id, 'unknown-but-taken');
    // ...а занятый другой строкой того же импорта заменяется новым.
    final second = _plan([
      _row(category: 'Спорт', categoryId: 'dup-id'),
      _row(category: 'Кино', categoryId: 'dup-id'),
    ]);
    expect(second.categoriesToCreate.map((c) => c.id), ['dup-id', 'new-1']);
  });

  test('id категории с чужим видом - ошибка строки', () {
    final plan = _plan(
      [_row(line: 5, categoryId: _salary)],
      categories: [_top(_salary, CategoryKind.income, 'Зарплата')],
    );
    expect(plan.errors.single, isA<CsvCategoryKindMismatch>());
    expect(plan.errors.single.line, 5);
    expect(plan.transactions, isEmpty);
    expect(plan.categoriesToCreate, isEmpty);
  });

  test('id категории указывает на подкатегорию - ошибка строки', () {
    final food = _top(_food, CategoryKind.expense, 'Еда');
    final plan = _plan(
      [_row(categoryId: _sub)],
      categories: [food, _child(_sub, food, 'Кафе')],
    );
    expect(plan.errors.single, isA<CsvCategoryIdIsSubcategory>());
  });

  test('подкатегория чужого родителя - ошибка строки', () {
    final food = _top(_food, CategoryKind.expense, 'Еда');
    final home = _top('cat-home', CategoryKind.expense, 'Дом');
    final plan = _plan(
      [_row(category: 'Дом', sub: 'Кафе', subcategoryId: _sub)],
      categories: [food, home, _child(_sub, food, 'Кафе')],
    );
    expect(plan.errors.single, isA<CsvSubcategoryWrongParent>());
    expect(plan.transactions, isEmpty);
  });

  test('id подкатегории указывает на категорию верхнего уровня - ошибка', () {
    final plan = _plan([_row(sub: 'Кафе', subcategoryId: _food)]);
    expect(plan.errors.single, isA<CsvSubcategoryWrongParent>());
  });

  test('подкатегория по id своего родителя находится', () {
    final food = _top(_food, CategoryKind.expense, 'Еда');
    final plan = _plan(
      [_row(sub: 'Другое имя', categoryId: _food, subcategoryId: _sub)],
      categories: [food, _child(_sub, food, 'Кафе')],
    );
    expect(plan.errors, isEmpty);
    expect(plan.transactions.single.subcategoryId, _sub);
    expect(plan.categoriesToCreate, isEmpty);
  });

  test('архивная категория: по id - операция в неё, по имени - новая', () {
    final archived = _top(_food, CategoryKind.expense, 'Еда', archived: true);
    final byId = _plan([_row(categoryId: _food)], categories: [archived]);
    expect(byId.transactions.single.categoryId, _food);
    expect(byId.categoriesToCreate, isEmpty);

    final byName = _plan([_row()], categories: [archived]);
    expect(byName.categoriesToCreate.single.name, 'Еда');
    expect(byName.transactions.single.categoryId, isNot(_food));
  });

  test('пропущенные строки не создают категорий', () {
    final plan = _plan(
      [
        _row(
          category: 'Новая',
          sub: 'Новая под',
          id: '0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeee1',
        ),
      ],
      live: {'0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeee1'},
    );
    expect(plan.categoriesToCreate, isEmpty);
    expect(plan.skippedExisting, 1);
  });

  test('новые категории встают в конец списка своего уровня', () {
    final plan = _plan([_row(category: 'Спорт'), _row(category: 'Кино')]);
    expect(plan.categoriesToCreate.map((c) => c.sortOrder), [4, 5]);
  });

  group('значки создаваемых категорий', () {
    test('известный ключ берётся, пустой и неизвестный - «Другое»', () {
      final plan = _plan([
        _accRow(
          category: 'Спорт',
          categoryIcon: 'star',
          sub: 'Зал',
          subIcon: 'no_such',
        ),
        _accRow(category: 'Кино'),
      ]);
      expect(plan.categoriesToCreate.map((c) => c.iconKey), [
        'star',
        csvImportCategoryIconKey,
        csvImportCategoryIconKey,
      ]);
    });

    test('у одной новой категории значок первой строки; существующая '
        'не меняется', () {
      final plan = _plan([
        _accRow(category: 'Спорт', categoryIcon: 'star'),
        _accRow(category: 'Спорт', categoryIcon: 'cart'),
        _accRow(category: 'Еда', categoryIcon: 'cart'),
      ]);
      expect(plan.categoriesToCreate.single.iconKey, 'star');
    });
  });

  group('счета', () {
    test('ключ значка счетов совпадает с ключом «Другое» в приложении', () {
      expect(csvImportAccountIconKey, otherAccountIconKey);
    });

    test('начальный остаток создаёт счёт; основным он не становится', () {
      final plan = _plan(
        const [],
        balances: [_ob('Карта', minor: -150000, id: 'ACC-1')],
        accounts: [_account('old', 'Наличные', sort: 4)],
      );
      final account = plan.accountsToCreate.single;
      expect(account.id, 'acc-1');
      expect(account.name, 'Карта');
      expect(account.openingBalance, Money.fromMinor(-150000, 'RUB'));
      expect(account.createdAt, DateTime.utc(2026, 9, 1, 8));
      expect(account.sortOrder, 5);
      expect(account.iconKey, csvImportAccountIconKey);
      expect(plan.errors, isEmpty);
    });

    test('существующий счёт (по id или имени): остаток не трогаем', () {
      final plan = _plan(
        const [],
        balances: [
          _ob('Другое имя', id: 'ACC-OLD'),
          _ob(' наличные '),
        ],
        accounts: [
          _account('acc-old', 'Карта', archived: true),
          _account('b', 'Наличные'),
        ],
      );
      expect(plan.accountsToCreate, isEmpty);
      expect(plan.errors, isEmpty);
    });

    test('Т11: второй остаток на тот же счёт', () {
      final plan = _plan(
        const [],
        balances: [_ob('Карта', line: 5), _ob('карта', line: 9)],
      );
      final error = plan.errors.single as CsvDuplicateOpeningBalance;
      expect((error.line, error.value, error.firstLine), (9, 'карта', 5));
      expect(plan.accountsToCreate, hasLength(1));
    });

    test('Т12: остаток в другой валюте у существующего счёта', () {
      final plan = _plan(
        const [],
        balances: [_ob('Карта', currency: 'EUR')],
        accounts: [_account('a', 'Карта', currency: 'USD')],
      );
      final error = plan.errors.single as CsvAccountCurrencyMismatch;
      expect(error.value, 'EUR');
      expect(error.accountName, 'Карта');
      expect(error.accountCurrency, 'USD');
    });

    test('операции привязываются к счёту по id и по имени', () {
      final plan = _plan(
        [_accRow(accountId: 'A'), _accRow(account: ' КАРТА '), _accRow()],
        accounts: [_account('a', 'Карта', archived: true)],
        balances: const [],
      );
      // Архивный по имени не находится: создаётся новый.
      final created = plan.accountsToCreate.single;
      expect(created.name, 'КАРТА');
      expect(plan.transactions.map((t) => t.accountId), [
        'a',
        created.id,
        null,
      ]);
    });

    test(
      'операция с неизвестным счётом создаёт рублёвый счёт с остатком 0',
      () {
        final plan = _plan([
          _accRow(account: 'Кошелёк'),
          _accRow(account: 'кошелёк'),
        ]);
        final account = plan.accountsToCreate.single;
        expect(account.openingBalance, Money.fromMinor(0, 'RUB'));
        expect(account.currencyDigits, 2);
        expect(account.createdAt, isNull);
        expect(plan.transactions.map((t) => t.accountId), [
          account.id,
          account.id,
        ]);
      },
    );

    test('Т12: валюта операции не совпадает со счётом - ошибка строки', () {
      final plan = _plan(
        [
          _accRow(account: 'Карта', currency: 'EUR'),
          _accRow(account: 'Новый', currency: 'USD'),
        ],
        accounts: [_account('a', 'Карта', currency: 'USD')],
      );
      final errors = plan.errors.cast<CsvAccountCurrencyMismatch>();
      expect(errors.map((e) => (e.value, e.accountName, e.accountCurrency)), [
        ('EUR', 'Карта', 'USD'),
        ('USD', 'Новый', 'RUB'),
      ]);
      expect(plan.accountsToCreate, isEmpty);
      expect(plan.transactions, isEmpty);
    });

    test('остаток в USD и операция в USD по этому счёту: ошибок нет', () {
      final plan = _plan(
        [_accRow(account: 'Доллары', currency: 'USD')],
        balances: [_ob('Доллары', currency: 'USD')],
      );
      expect(plan.errors, isEmpty);
      expect(
        plan.transactions.single.accountId,
        plan.accountsToCreate.single.id,
      );
    });

    test('id счёта из файла занят или удалён: новый id', () {
      final plan = _plan(
        const [],
        balances: [_ob('Карта', id: 'GONE')],
        deletedAccounts: {'gone'},
      );
      expect(plan.accountsToCreate.single.id, 'new-1');
    });

    group('правки ревью 5.18b', () {
      const idA = 'aaaaaaaa-0000-4000-8000-000000000001';
      const idB = 'bbbbbbbb-0000-4000-8000-000000000002';

      test('архивная и активная «Карта» с разными id: два счёта', () {
        final plan = _plan(
          [_accRow(accountId: idA), _accRow(accountId: idB)],
          balances: [
            _ob('Карта', id: idA, minor: 100),
            _ob('Карта', id: idB, line: 3, minor: 250),
          ],
        );
        expect(plan.errors, isEmpty);
        expect(plan.accountsToCreate.map((a) => (a.id, a.name)), [
          (idA, 'Карта'),
          (idB, 'Карта (2)'),
        ]);
        expect(plan.accountsToCreate.map((a) => a.openingBalance.minorUnits), [
          100,
          250,
        ]);
        expect(plan.transactions.map((t) => t.accountId), [idA, idB]);
      });

      test('повторный импорт того же файла ничего не создаёт', () {
        final rows = [_accRow(accountId: idA), _accRow(accountId: idB)];
        final balances = [
          _ob('Карта', id: idA),
          _ob('Карта', id: idB, line: 3),
        ];
        final first = _plan(rows, balances: balances);
        final second = _plan(
          rows,
          balances: balances,
          accounts: first.accountsToCreate,
        );
        expect(second.accountsToCreate, isEmpty);
        expect(second.errors, isEmpty);
        expect(second.skippedExisting, 2);
        expect(second.transactions.map((t) => t.accountId), [idA, idB]);
      });

      test('имя на 40 символов получает суффикс и не длиннее 40', () {
        final name = 'Я' * 40;
        final plan = _plan(
          const [],
          balances: [
            _ob(name, id: idA),
            _ob(name, id: idB, line: 3),
          ],
        );
        final renamed = plan.accountsToCreate[1].name;
        expect(renamed, '${'Я' * 36} (2)');
        expect(renamed.runes.length, 40);
      });

      test('«Карта (2)» занята - «Карта (3)»', () {
        final plan = _plan(
          const [],
          balances: [_ob('Карта', id: idB)],
          accounts: [_account('x', 'Карта'), _account('y', 'карта (2)')],
        );
        expect(plan.accountsToCreate.single.name, 'Карта (3)');
      });

      test('два остатка с одним id - Т11, с разными id и именем - нет', () {
        final dup = _plan(
          const [],
          balances: [
            _ob('Карта', id: idA, line: 5),
            _ob('Другое имя', id: idA, line: 9),
          ],
        );
        final error = dup.errors.single as CsvDuplicateOpeningBalance;
        expect((error.line, error.firstLine), (9, 5));
      });

      test('пропущенный начальный остаток входит в skippedExisting', () {
        final plan = _plan(
          const [],
          balances: [
            _ob('Карта', id: 'acc-1'),
            _ob('Наличные', line: 3),
            _ob('Новый', line: 4),
          ],
          accounts: [_account('acc-1', 'Карта'), _account('b', 'Наличные')],
        );
        expect(plan.skippedExisting, 2);
        expect(plan.accountsToCreate.single.name, 'Новый');
      });

      test('операция с неизвестным id счёта без имени - ошибка строки', () {
        final plan = _plan([_accRow(accountId: idA)]);
        final error = plan.errors.single as CsvAccountIdNotFound;
        expect((error.line, error.value), (7, idA));
        expect(plan.transactions, isEmpty);
        expect(plan.accountsToCreate, isEmpty);
      });

      test('«1,5000» у известной своей валюты с 2 знаками - 1,50', () {
        final plan = _plan(
          const [],
          balances: [
            _ob('Новый', minor: 15000, currency: 'XYZ', customDigits: 4),
            _ob('Ещё', minor: 15001, currency: 'XYZ', customDigits: 4, line: 3),
          ],
          accounts: [_account('a', 'Старый', currency: 'XYZ', digits: 2)],
        );
        expect(plan.accountsToCreate.single.openingBalance.minorUnits, 150);
        expect(plan.errors.single.line, 3);
      });
    });

    test('архивный счёт того же имени не мешает создать новый', () {
      final plan = _plan(
        const [],
        balances: [_ob('Карта')],
        accounts: [_account('a', 'Карта', archived: true)],
      );
      expect(plan.accountsToCreate.single.name, 'Карта');
    });
  });

  group('валюты начального остатка', () {
    test('валюта каталога: знаки из каталога', () {
      final plan = _plan(
        const [],
        balances: [_ob('Йены', minor: 5000, currency: 'JPY')],
      );
      expect(plan.accountsToCreate.single.currencyDigits, 0);
    });

    test('новая своя валюта: знаки из файла', () {
      final plan = _plan(
        const [],
        balances: [_ob('Кошелёк', minor: 15, currency: 'XYZ', customDigits: 4)],
      );
      final account = plan.accountsToCreate.single;
      expect(account.currencyDigits, 4);
      expect(account.openingBalance, Money.fromMinor(15, 'XYZ'));
    });

    test('своя валюта уже известна: знаки оттуда, сумма пересчитана', () {
      final plan = _plan(
        const [],
        balances: [_ob('Новый', minor: 55, currency: 'XYZ', customDigits: 1)],
        accounts: [_account('a', 'Старый', currency: 'XYZ', digits: 3)],
      );
      final account = plan.accountsToCreate.single;
      expect(account.currencyDigits, 3);
      expect(account.openingBalance.minorUnits, 5500);
    });

    test('Т9: у известной своей валюты в файле больше знаков', () {
      final plan = _plan(
        const [],
        balances: [
          _ob('Новый', minor: -12345, currency: 'XYZ', customDigits: 3),
        ],
        accounts: [_account('a', 'Старый', currency: 'XYZ', digits: 2)],
      );
      final error = plan.errors.single as CsvInvalidAmount;
      expect(error.value, '-12,345');
      expect(error.failure, AmountParseFailure.tooManyDecimals);
      expect((error.currencyCode, error.currencyDigits), ('XYZ', 2));
      expect(error.digitsFromFile, isFalse);
      expect(plan.accountsToCreate, isEmpty);
    });

    test('две новые строки одной своей валюты с разными знаками: ошибка', () {
      final plan = _plan(
        const [],
        balances: [
          _ob('А', minor: 1, currency: 'XYZ', customDigits: 1),
          _ob('Б', minor: 12, currency: 'XYZ', customDigits: 2, line: 3),
        ],
      );
      expect(plan.accountsToCreate.single.name, 'А');
      expect(plan.errors.single, isA<CsvInvalidAmount>());
      expect(plan.errors.single.line, 3);
    });
  });
}
