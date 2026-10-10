import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/csv/csv_codec.dart';
import 'package:money_app/core/errors/data_corrupted_exception.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/transfer.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/export/domain/transactions_export.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/fixed_clock.dart';

final _cafe = Category.topLevel(
  id: 'cat',
  kind: CategoryKind.expense,
  name: 'Кафе',
  iconKey: 'icon',
  sortOrder: 0,
);

final _coffee = Category(
  id: 'sub',
  kind: CategoryKind.expense,
  name: 'Кофе',
  iconKey: 'sub-icon',
  parentId: 'cat',
  sortOrder: 0,
);

final _salary = Category.topLevel(
  id: 'inc',
  kind: CategoryKind.income,
  name: 'Зарплата',
  iconKey: 'inc-icon',
  sortOrder: 0,
);

final _categories = [_cafe, _coffee, _salary];

/// Операция с разумными значениями по умолчанию: расход 350,00 в «Кафе».
Transaction _tx(
  String id, {
  TransactionType type = TransactionType.expense,
  int minor = 35000,
  DateOnly? day,
  DateTime? at,
  String categoryId = 'cat',
  String? subcategoryId,
  String? note,
  String? accountId,
  String currency = 'RUB',
}) {
  final onDay = day ?? DateOnly(2026, 10, 4);
  return Transaction(
    id: id,
    type: type,
    amount: Money.fromMinor(minor, currency),
    occurredOn: onDay,
    occurredAt: at ?? DateTime.utc(2026, 10, 4, 9, 15),
    categoryId: categoryId,
    subcategoryId: subcategoryId,
    note: note,
    accountId: accountId,
  );
}

/// Счёт, созданный 4 октября 2026 в полдень UTC (день один в любом поясе).
Account _acc(
  String id,
  String name, {
  int minor = 0,
  String currency = 'RUB',
  int digits = 2,
  DateTime? archivedAt,
  DateTime? createdAt,
}) {
  return Account(
    id: id,
    name: name,
    iconKey: 'wallet',
    openingBalance: Money.fromMinor(minor, currency),
    sortOrder: 0,
    currencyDigits: digits,
    archivedAt: archivedAt,
    createdAt: createdAt ?? DateTime.utc(2026, 10, 4, 12),
  );
}

void main() {
  group('formatCsvAmount: сумма через целую арифметику', () {
    test('35000 копеек — это 350,00', () {
      expect(formatCsvAmount(Money.fromMinor(35000, 'RUB')), '350,00');
    });

    test('5 копеек — это 0,05 (копейки дополняются нулём)', () {
      expect(formatCsvAmount(Money.fromMinor(5, 'RUB')), '0,05');
    });

    test('1 копейка — это 0,01', () {
      expect(formatCsvAmount(Money.fromMinor(1, 'RUB')), '0,01');
    });

    test('ноль — это 0,00', () {
      expect(formatCsvAmount(Money.zero('RUB')), '0,00');
    });

    test('без пробела-разряда: 100000 копеек — это 1000,00', () {
      expect(formatCsvAmount(Money.fromMinor(100000, 'RUB')), '1000,00');
    });

    test('большая сумма: 1234567 копеек — это 12345,67', () {
      expect(formatCsvAmount(Money.fromMinor(1234567, 'RUB')), '12345,67');
    });

    test('отрицательная сумма не выгружается (ArgumentError)', () {
      expect(
        () => formatCsvAmount(Money.fromMinor(-1, 'RUB')),
        throwsArgumentError,
      );
    });
  });

  group('formatCsvDate: дата ДД.ММ.ГГГГ', () {
    test('04.10.2026', () {
      expect(formatCsvDate(DateOnly(2026, 10, 4)), '04.10.2026');
    });

    test('ведущие нули в дне и месяце: 09.01.2026', () {
      expect(formatCsvDate(DateOnly(2026, 1, 9)), '09.01.2026');
    });
  });

  group('строка экспорта', () {
    test('заголовки в принятом порядке, 17 колонок', () {
      final rows = buildTransactionsCsvRows(
        transactions: const [],
        categories: _categories,
        accounts: const [],
      );
      expect(rows, hasLength(1));
      expect(rows.first, [
        'Дата',
        'Тип',
        'Сумма',
        'Валюта',
        'Категория',
        'Подкатегория',
        'Комментарий',
        'Счёт',
        'Счёт зачисления',
        'ID операции',
        'ID категории',
        'ID подкатегории',
        'Время операции (UTC)',
        'ID счёта',
        'ID счёта зачисления',
        'Значок категории',
        'Значок подкатегории',
      ]);
    });

    test('расход с подкатегорией и комментарием: все колонки на месте', () {
      final rows = buildTransactionsCsvRows(
        transactions: [
          _tx(
            'id-1',
            subcategoryId: 'sub',
            note: 'с Машей',
            at: DateTime.utc(2026, 10, 4, 9, 15),
          ),
        ],
        categories: _categories,
        accounts: const [],
      );
      expect(rows[1], [
        '04.10.2026',
        'Расход',
        '-350,00',
        'RUB',
        'Кафе',
        'Кофе',
        'с Машей',
        '',
        '',
        'id-1',
        'cat',
        'sub',
        '2026-10-04T09:15:00.000Z',
        '',
        '',
        'icon',
        'sub-icon',
      ]);
    });

    test('расход на 0,05 — это -0,05 (минус перед числом)', () {
      final rows = buildTransactionsCsvRows(
        transactions: [_tx('small', minor: 5)],
        categories: _categories,
        accounts: const [],
      );
      expect(rows[1][2], '-0,05');
    });

    test('расход на ноль выгружается как 0,00 без минуса', () {
      final rows = buildTransactionsCsvRows(
        transactions: [_tx('zero', minor: 0)],
        categories: _categories,
        accounts: const [],
      );
      expect(rows[1][1], 'Расход');
      expect(rows[1][2], '0,00');
    });

    test('доход на ноль — тоже 0,00', () {
      final rows = buildTransactionsCsvRows(
        transactions: [
          _tx(
            'inc-zero',
            type: TransactionType.income,
            minor: 0,
            categoryId: 'inc',
          ),
        ],
        categories: _categories,
        accounts: const [],
      );
      expect(rows[1][2], '0,00');
    });

    test('доход без подкатегории и комментария: пустые ячейки', () {
      final rows = buildTransactionsCsvRows(
        transactions: [
          _tx(
            'inc-1',
            type: TransactionType.income,
            minor: 12000050,
            categoryId: 'inc',
          ),
        ],
        categories: _categories,
        accounts: const [],
      );
      expect(rows[1], [
        '04.10.2026',
        'Доход',
        '120000,50',
        'RUB',
        'Зарплата',
        '',
        '',
        '',
        '',
        'inc-1',
        'inc',
        '',
        '2026-10-04T09:15:00.000Z',
        '',
        '',
        'inc-icon',
        '',
      ]);
    });

    test('дата берётся из occurredOn, а не пересчётом из UTC', () {
      // 03.10 в 22:30 UTC — в Москве уже 04.10, но операция записана
      // как день 04.10: файл обязан показать тот день, который выбрал человек.
      final rows = buildTransactionsCsvRows(
        transactions: [
          _tx(
            'd',
            day: DateOnly(2026, 10, 4),
            at: DateTime.utc(2026, 10, 3, 22, 30),
          ),
        ],
        categories: _categories,
        accounts: const [],
      );
      expect(rows[1][0], '04.10.2026');
      expect(rows[1][12], '2026-10-03T22:30:00.000Z');
    });

    test('операция в архивной категории выгружается с её именем', () {
      final archivedCafe = _cafe.archived(DateTime.utc(2026, 9, 1));
      final rows = buildTransactionsCsvRows(
        transactions: [_tx('old')],
        categories: [archivedCafe],
        accounts: const [],
      );
      expect(rows[1][4], 'Кафе');
    });

    test('нет категории у операции — DataCorruptedException', () {
      expect(
        () => buildTransactionsCsvRows(
          transactions: [_tx('orphan', categoryId: 'missing')],
          categories: _categories,
          accounts: const [],
        ),
        throwsA(isA<DataCorruptedException>()),
      );
    });

    test('нет подкатегории у операции — DataCorruptedException', () {
      expect(
        () => buildTransactionsCsvRows(
          transactions: [_tx('orphan', subcategoryId: 'missing')],
          categories: _categories,
          accounts: const [],
        ),
        throwsA(isA<DataCorruptedException>()),
      );
    });
  });

  group('счета: колонки и строки «Начальный остаток» (ADR 0010, п. 10)', () {
    List<List<String>> rowsOf(
      List<Transaction> transactions,
      List<Account> accounts,
    ) => buildTransactionsCsvRows(
      transactions: transactions,
      categories: _categories,
      accounts: accounts,
    );

    test('операция со счётом: имя и id счёта, колонки зачисления пусты', () {
      final rows = rowsOf([_tx('t', accountId: 'a1')], [_acc('a1', 'Карта')]);
      final row = rows[1];
      expect(row[7], 'Карта');
      expect(row[8], '');
      expect(row[13], 'a1');
      expect(row[14], '');
    });

    test('операция без счёта: ячейки счёта пусты', () {
      final row = rowsOf([_tx('t')], const [])[1];
      expect([row[7], row[8], row[13], row[14]], ['', '', '', '']);
    });

    test('счёт операции не найден: DataCorruptedException', () {
      expect(
        () => rowsOf([_tx('t', accountId: 'gone')], [_acc('a1', 'Карта')]),
        throwsA(isA<DataCorruptedException>()),
      );
    });

    test('начальный остаток положительный: все ячейки строки', () {
      final rows = rowsOf(const [], [_acc('a1', 'Карта', minor: 1200000)]);
      expect(rows, hasLength(2));
      expect(rows[1], [
        '04.10.2026',
        'Начальный остаток',
        '12000,00',
        'RUB',
        '',
        '',
        '',
        'Карта',
        '',
        '',
        '',
        '',
        '2026-10-04T12:00:00.000Z',
        'a1',
        '',
        '',
        '',
      ]);
    });

    test('начальный остаток отрицательный: -1500,00', () {
      final rows = rowsOf(const [], [_acc('a1', 'Кредитка', minor: -150000)]);
      expect(rows[1][2], '-1500,00');
    });

    test('начальный остаток нулевой: 0,00 без знака', () {
      final rows = rowsOf(const [], [_acc('a1', 'Наличные')]);
      expect(rows[1][2], '0,00');
    });

    test('архивный счёт тоже выгружается', () {
      final rows = rowsOf(const [], [
        _acc('a1', 'Старая', archivedAt: DateTime.utc(2026, 9, 1)),
      ]);
      expect(rows, hasLength(2));
      expect(rows[1][1], 'Начальный остаток');
      expect(rows[1][7], 'Старая');
    });

    test('счёт без момента создания: DataCorruptedException', () {
      final noTime = Account(
        id: 'a1',
        name: 'Карта',
        iconKey: 'wallet',
        openingBalance: Money.zero('RUB'),
        sortOrder: 0,
        currencyDigits: 2,
      );
      expect(
        () => rowsOf(const [], [noTime]),
        throwsA(isA<DataCorruptedException>()),
      );
    });

    test('порядок: день, момент, id; остаток идёт первым при равенстве', () {
      final rows = rowsOf(
        [
          _tx('later', at: DateTime.utc(2026, 10, 4, 13)),
          _tx('same', at: DateTime.utc(2026, 10, 4, 12)),
          _tx('before', at: DateTime.utc(2026, 10, 4, 9)),
        ],
        [_acc('b', 'Б'), _acc('a', 'А')],
      );
      expect(
        [for (final r in rows.skip(1)) '${r[1]}:${r[9]}:${r[13]}'],
        [
          'Расход:before:',
          'Начальный остаток::a',
          'Начальный остаток::b',
          'Расход:same:',
          'Расход:later:',
        ],
      );
    });

    test('«туда и обратно» через кодек: имена с ; и кавычками', () {
      final text = buildTransactionsCsv(
        transactions: [_tx('t', accountId: 'a1')],
        categories: _categories,
        accounts: [_acc('a1', 'Карта; "основная"', minor: -5)],
      );
      final rows = decodeCsv(text);
      expect(rows, hasLength(3));
      expect(rows.every((r) => r.length == 17), isTrue);
      expect(rows[1][2], '-350,00');
      expect(rows[1][7], 'Карта; "основная"');
      expect(rows[2][2], '-0,05');
      expect(rows[2][7], 'Карта; "основная"');
    });
  });

  group('валюты: знаки каждой валюты (ADR 0010, п. 16.11)', () {
    List<String> rowFor(Transaction t, List<Account> accounts) =>
        buildTransactionsCsvRows(
          transactions: [t],
          categories: _categories,
          accounts: accounts,
        )[1];

    test('счёт BTC с остатком 0,00150000', () {
      final rows = buildTransactionsCsvRows(
        transactions: const [],
        categories: _categories,
        accounts: [
          _acc('b', 'Кошелёк', minor: 150000, currency: 'BTC', digits: 8),
        ],
      );
      expect(rows[1][2], '0,00150000');
      expect(rows[1][3], 'BTC');
    });

    test('своя валюта ABC с 4 знаками: 12,3456', () {
      final rows = buildTransactionsCsvRows(
        transactions: const [],
        categories: _categories,
        accounts: [
          _acc('c', 'Свой', minor: 123456, currency: 'ABC', digits: 4),
        ],
      );
      expect(rows[1][2], '12,3456');
      expect(rows[1][3], 'ABC');
    });

    test('расход в USD без счёта: валюта строки и два знака', () {
      final row = rowFor(_tx('u', minor: 1250, currency: 'USD'), const []);
      expect(row[2], '-12,50');
      expect(row[3], 'USD');
    });

    test('операция на счёте ABC берёт знаки счёта', () {
      final row = rowFor(
        _tx('x', minor: 123456, currency: 'ABC', accountId: 'c'),
        [_acc('c', 'Свой', currency: 'ABC', digits: 4)],
      );
      expect(row[2], '-12,3456');
      expect(row[3], 'ABC');
    });

    test('иена без знаков после запятой: 1500', () {
      final row = rowFor(_tx('j', minor: 1500, currency: 'JPY'), const []);
      expect(row[2], '-1500');
    });
  });

  group('значки категорий (ADR 0010, п. 17)', () {
    Category cat(String id, String icon, {String? parentId}) => Category(
      id: id,
      kind: CategoryKind.expense,
      name: 'Имя $id',
      iconKey: icon,
      parentId: parentId,
      sortOrder: 0,
    );

    List<List<String>> rowsOf(
      List<Transaction> transactions,
      List<Category> categories, [
      List<Account> accounts = const [],
    ]) => buildTransactionsCsvRows(
      transactions: transactions,
      categories: categories,
      accounts: accounts,
    );

    test('категория local_cafe и подкатегория glyph:Ж пишутся ключом', () {
      final rows = rowsOf(
        [_tx('t', categoryId: 'c', subcategoryId: 's')],
        [cat('c', 'local_cafe'), cat('s', 'glyph:Ж', parentId: 'c')],
      );
      expect(rows[1][15], 'local_cafe');
      expect(rows[1][16], 'glyph:Ж');
    });

    test('без подкатегории значок подкатегории пуст', () {
      final rows = rowsOf(
        [_tx('t', categoryId: 'c')],
        [cat('c', 'local_cafe')],
      );
      expect(rows[1][15], 'local_cafe');
      expect(rows[1][16], '');
    });

    test('незнакомый ключ пишется как есть', () {
      // Греческая омега (код 0x3A9), собранная кодом: в исходнике без escape.
      final omega = 'glyph:${String.fromCharCode(0x3A9)}';
      final rows = rowsOf(
        [_tx('t', categoryId: 'c', subcategoryId: 's')],
        [cat('c', omega), cat('s', 'no_such_icon', parentId: 'c')],
      );
      expect(rows[1][15], omega);
      expect(rows[1][16], 'no_such_icon');
    });

    test('«Начальный остаток»: обе ячейки значков пусты', () {
      final rows = rowsOf(const [], _categories, [_acc('a', 'Карта')]);
      expect(rows[1][15], '');
      expect(rows[1][16], '');
    });
  });

  group('порядок строк: день, затем момент, затем id', () {
    List<String> idsIn(List<List<String>> rows) => [
      for (final row in rows.skip(1)) row[9],
    ];

    test('одинаковый день: сортировка по времени, а не по id', () {
      final rows = buildTransactionsCsvRows(
        transactions: [
          _tx('a', at: DateTime.utc(2026, 10, 4, 12)),
          _tx('z', at: DateTime.utc(2026, 10, 4, 9)),
        ],
        categories: _categories,
        accounts: const [],
      );
      expect(idsIn(rows), ['z', 'a']);
    });

    test('одинаковый день и момент: сортировка по id', () {
      final rows = buildTransactionsCsvRows(
        transactions: [_tx('b'), _tx('a'), _tx('c')],
        categories: _categories,
        accounts: const [],
      );
      expect(idsIn(rows), ['a', 'b', 'c']);
    });

    test('день важнее момента: более ранний день идёт первым', () {
      final rows = buildTransactionsCsvRows(
        transactions: [
          _tx(
            'later-day',
            day: DateOnly(2026, 10, 5),
            at: DateTime.utc(2026, 10, 4, 1),
          ),
          _tx(
            'earlier-day',
            day: DateOnly(2026, 10, 4),
            at: DateTime.utc(2026, 10, 4, 23),
          ),
        ],
        categories: _categories,
        accounts: const [],
      );
      expect(idsIn(rows), ['earlier-day', 'later-day']);
    });
  });

  group('переводы (ADR 0010, п. 10)', () {
    Transfer transfer(
      String id, {
      String from = 'a',
      String to = 'b',
      int minor = 150000,
      String currency = 'RUB',
      DateTime? at,
      String? note,
    }) {
      final moment = at ?? DateTime.utc(2026, 10, 4, 10);
      return Transfer(
        id: id,
        fromAccountId: from,
        toAccountId: to,
        amount: Money.fromMinor(minor, currency),
        occurredOn: DateOnly.fromDateTime(moment),
        occurredAt: moment,
        note: note,
      );
    }

    List<List<String>> rowsWith(
      List<Transfer> transfers, {
      List<Transaction> transactions = const [],
      List<Account>? accounts,
    }) => buildTransactionsCsvRows(
      transactions: transactions,
      categories: _categories,
      accounts: accounts ?? [_acc('a', 'Карта'), _acc('b', 'Наличные')],
      transfers: transfers,
    );

    List<String> lastTransfer(List<List<String>> rows) =>
        rows.lastWhere((r) => r[1] == 'Перевод');

    test('строка Перевод: сумма без знака, оба счёта, комментарий', () {
      final rows = rowsWith([transfer('t1', note: 'Снял в банкомате')]);
      final row = lastTransfer(rows);
      expect(row, [
        '04.10.2026',
        'Перевод',
        '1500,00',
        'RUB',
        '',
        '',
        'Снял в банкомате',
        'Карта',
        'Наличные',
        't1',
        '',
        '',
        '2026-10-04T10:00:00.000Z',
        'a',
        'b',
        '',
        '',
      ]);
    });

    test('BTC: знаки валюты счёта, 8 цифр', () {
      final rows = rowsWith(
        [transfer('t1', minor: 150000, currency: 'BTC')],
        accounts: [
          _acc('a', 'Кошелёк', currency: 'BTC', digits: 8),
          _acc('b', 'Биржа', currency: 'BTC', digits: 8),
        ],
      );
      expect(lastTransfer(rows)[2], '0,00150000');
      expect(lastTransfer(rows)[3], 'BTC');
    });

    test('своя валюта ABC с 4 знаками', () {
      final rows = rowsWith(
        [transfer('t1', minor: 123456, currency: 'ABC')],
        accounts: [
          _acc('a', 'Свой', currency: 'ABC', digits: 4),
          _acc('b', 'Другой', currency: 'ABC', digits: 4),
        ],
      );
      expect(lastTransfer(rows)[2], '12,3456');
    });

    test('порядок: день, момент, id вперемешку с операциями', () {
      final rows = rowsWith(
        [
          transfer('t-late', at: DateTime.utc(2026, 10, 4, 12)),
          transfer('t-early', at: DateTime.utc(2026, 10, 4, 8)),
        ],
        transactions: [_tx('mid', at: DateTime.utc(2026, 10, 4, 10))],
      );
      expect(
        [
          for (final r in rows.skip(1))
            if (r[9].isNotEmpty) r[9],
        ],
        ['t-early', 'mid', 't-late'],
      );
    });

    test('счёт перевода не найден: отказ экспорта', () {
      expect(
        () => rowsWith([transfer('t1', to: 'missing')]),
        throwsA(isA<DataCorruptedException>()),
      );
    });
  });

  group('кодирование и обратное чтение', () {
    test('комментарий с ;, кавычкой и переносом строки сохраняется', () {
      const note = 'кофе; "булка"\nи чай';
      final text = buildTransactionsCsv(
        transactions: [_tx('n', note: note)],
        categories: _categories,
        accounts: const [],
      );
      final rows = decodeCsv(text);
      expect(rows, hasLength(2));
      expect(rows[1][6], note);
      expect(rows[1][9], 'n');
    });

    test('названия категорий с ; и кавычками тоже сохраняются', () {
      final weird = Category.topLevel(
        id: 'w',
        kind: CategoryKind.expense,
        name: 'Еда; "быт"',
        iconKey: 'icon',
        sortOrder: 0,
      );
      final text = buildTransactionsCsv(
        transactions: [_tx('w1', categoryId: 'w')],
        categories: [weird],
        accounts: const [],
      );
      expect(decodeCsv(text)[1][4], 'Еда; "быт"');
    });

    test('файл начинается с BOM и содержит только заголовки без операций', () {
      final text = buildTransactionsCsv(
        transactions: const [],
        categories: _categories,
        accounts: const [],
      );
      expect(text.startsWith('\uFEFF'), isTrue);
      expect(decodeCsv(text), hasLength(1));
    });
  });

  group('exportFileName: zuno-export-ГГГГ-ММ-ДД.csv', () {
    test('берёт локальный день из часов', () {
      final clock = FixedClock(DateTime(2026, 10, 4, 23, 30));
      expect(exportFileName(clock), 'zuno-export-2026-10-04.csv');
    });

    test('ведущие нули в месяце и дне', () {
      final clock = FixedClock(DateTime(2026, 1, 9, 0, 5));
      expect(exportFileName(clock), 'zuno-export-2026-01-09.csv');
    });
  });
}
