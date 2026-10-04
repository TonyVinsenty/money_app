import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/csv/csv_codec.dart';
import 'package:money_app/core/errors/data_corrupted_exception.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
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
  iconKey: 'icon',
  parentId: 'cat',
  sortOrder: 0,
);

final _salary = Category.topLevel(
  id: 'inc',
  kind: CategoryKind.income,
  name: 'Зарплата',
  iconKey: 'icon',
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
}) {
  final onDay = day ?? DateOnly(2026, 10, 4);
  return Transaction(
    id: id,
    type: type,
    amount: Money.fromMinor(minor, 'RUB'),
    occurredOn: onDay,
    occurredAt: at ?? DateTime.utc(2026, 10, 4, 9, 15),
    categoryId: categoryId,
    subcategoryId: subcategoryId,
    note: note,
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
    test('заголовки в принятом порядке, 11 колонок', () {
      final rows = buildTransactionsCsvRows(
        transactions: const [],
        categories: _categories,
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
        'ID операции',
        'ID категории',
        'ID подкатегории',
        'Время операции (UTC)',
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
      );
      expect(rows[1], [
        '04.10.2026',
        'Расход',
        '-350,00',
        'RUB',
        'Кафе',
        'Кофе',
        'с Машей',
        'id-1',
        'cat',
        'sub',
        '2026-10-04T09:15:00.000Z',
      ]);
    });

    test('расход на 0,05 — это -0,05 (минус перед числом)', () {
      final rows = buildTransactionsCsvRows(
        transactions: [_tx('small', minor: 5)],
        categories: _categories,
      );
      expect(rows[1][2], '-0,05');
    });

    test('расход на ноль выгружается как 0,00 без минуса', () {
      final rows = buildTransactionsCsvRows(
        transactions: [_tx('zero', minor: 0)],
        categories: _categories,
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
      );
      expect(rows[1], [
        '04.10.2026',
        'Доход',
        '120000,50',
        'RUB',
        'Зарплата',
        '',
        '',
        'inc-1',
        'inc',
        '',
        '2026-10-04T09:15:00.000Z',
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
      );
      expect(rows[1][0], '04.10.2026');
      expect(rows[1][10], '2026-10-03T22:30:00.000Z');
    });

    test('операция в архивной категории выгружается с её именем', () {
      final archivedCafe = _cafe.archived(DateTime.utc(2026, 9, 1));
      final rows = buildTransactionsCsvRows(
        transactions: [_tx('old')],
        categories: [archivedCafe],
      );
      expect(rows[1][4], 'Кафе');
    });

    test('нет категории у операции — DataCorruptedException', () {
      expect(
        () => buildTransactionsCsvRows(
          transactions: [_tx('orphan', categoryId: 'missing')],
          categories: _categories,
        ),
        throwsA(isA<DataCorruptedException>()),
      );
    });

    test('нет подкатегории у операции — DataCorruptedException', () {
      expect(
        () => buildTransactionsCsvRows(
          transactions: [_tx('orphan', subcategoryId: 'missing')],
          categories: _categories,
        ),
        throwsA(isA<DataCorruptedException>()),
      );
    });
  });

  group('порядок строк: день, затем момент, затем id', () {
    List<String> idsIn(List<List<String>> rows) => [
      for (final row in rows.skip(1)) row[7],
    ];

    test('одинаковый день: сортировка по времени, а не по id', () {
      final rows = buildTransactionsCsvRows(
        transactions: [
          _tx('a', at: DateTime.utc(2026, 10, 4, 12)),
          _tx('z', at: DateTime.utc(2026, 10, 4, 9)),
        ],
        categories: _categories,
      );
      expect(idsIn(rows), ['z', 'a']);
    });

    test('одинаковый день и момент: сортировка по id', () {
      final rows = buildTransactionsCsvRows(
        transactions: [_tx('b'), _tx('a'), _tx('c')],
        categories: _categories,
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
      );
      expect(idsIn(rows), ['earlier-day', 'later-day']);
    });
  });

  group('кодирование и обратное чтение', () {
    test('комментарий с ;, кавычкой и переносом строки сохраняется', () {
      const note = 'кофе; "булка"\nи чай';
      final text = buildTransactionsCsv(
        transactions: [_tx('n', note: note)],
        categories: _categories,
      );
      final rows = decodeCsv(text);
      expect(rows, hasLength(2));
      expect(rows[1][6], note);
      expect(rows[1][7], 'n');
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
      );
      expect(decodeCsv(text)[1][4], 'Еда; "быт"');
    });

    test('файл начинается с BOM и содержит только заголовки без операций', () {
      final text = buildTransactionsCsv(
        transactions: const [],
        categories: _categories,
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
