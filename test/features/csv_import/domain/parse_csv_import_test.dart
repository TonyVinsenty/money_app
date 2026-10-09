import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/money/parse_amount.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/csv_import/domain/csv_import_failures.dart';
import 'package:money_app/features/csv_import/domain/parse_csv_import.dart';
import 'package:money_app/features/export/domain/transactions_export.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/fixed_clock.dart';

// Сегодня 7 октября 2026, 09:30 по местному времени.
final _now = DateTime(2026, 10, 7, 9, 30);
final _clock = FixedClock(_now);
const _id1 = '0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeee1';
const _id2 = '0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeee2';

const _header = 'Дата;Тип;Сумма;Категория';

/// Разбирает текст как UTF-8 файл.
CsvImportParseResult _parse(String text) =>
    parseCsvImport(utf8.encode(text), clock: _clock);

CsvImportParsed _parsed(String text) {
  final result = _parse(text);
  expect(result, isA<CsvImportParsed>());
  return result as CsvImportParsed;
}

/// Ошибки одной строки с минимальными колонками.
List<CsvRowError> _errorsOf(String row) =>
    _parsed('$_header\r\n$row\r\n').errors;

CsvFileFailure _failureOf(String text) {
  final result = _parse(text);
  expect(result, isA<CsvImportFileFailed>());
  return (result as CsvImportFileFailed).failure;
}

void main() {
  group('наш собственный экспорт', () {
    final cafe = Category.topLevel(
      id: '0199aaaa-0000-7000-8000-000000000001',
      kind: CategoryKind.expense,
      name: 'Кафе',
      iconKey: 'icon',
      sortOrder: 0,
    );
    final coffee = Category(
      id: '0199aaaa-0000-7000-8000-000000000002',
      kind: CategoryKind.expense,
      name: 'Кофе',
      iconKey: 'icon',
      parentId: cafe.id,
      sortOrder: 0,
    );
    final salary = Category.topLevel(
      id: '0199aaaa-0000-7000-8000-000000000003',
      kind: CategoryKind.income,
      name: 'Зарплата',
      iconKey: 'icon',
      sortOrder: 0,
    );
    final transactions = [
      Transaction(
        id: _id1,
        type: TransactionType.expense,
        amount: Money.fromMinor(35050, 'RUB'),
        occurredOn: DateOnly(2026, 10, 4),
        occurredAt: DateTime.utc(2026, 10, 4, 9, 15, 30, 123),
        categoryId: cafe.id,
        subcategoryId: coffee.id,
        note: 'с "молоком";\nдва раза',
      ),
      Transaction(
        id: _id2,
        type: TransactionType.income,
        amount: Money.fromMinor(10000000, 'RUB'),
        occurredOn: DateOnly(2026, 10, 5),
        occurredAt: DateTime.utc(2026, 10, 5, 8),
        categoryId: salary.id,
      ),
    ];

    test('разбирается без ошибок и совпадает с исходными операциями', () {
      final csv = buildTransactionsCsv(
        transactions: transactions,
        categories: [cafe, coffee, salary],
        accounts: const [],
      );
      final result = _parsed(csv);

      expect(result.errors, isEmpty);
      expect(result.rows, hasLength(2));
      for (var i = 0; i < 2; i++) {
        final row = result.rows[i];
        final tx = transactions[i];
        expect(row.transactionId, tx.id);
        expect(row.type, tx.type);
        expect(row.amount, tx.amount);
        expect(row.day, tx.occurredOn);
        expect(row.occurredAt, tx.occurredAt);
        expect(row.note, tx.note);
        expect(row.categoryId, tx.categoryId);
        expect(row.subcategoryId, tx.subcategoryId);
      }
      expect(result.rows[0].categoryName, 'Кафе');
      expect(result.rows[0].subcategoryName, 'Кофе');
      expect(result.rows[1].subcategoryName, isNull);
      // Комментарий с переносом занимает в Excel одну строку.
      expect(result.rows.map((r) => r.line), [2, 3]);
    });
  });

  group('файл и заголовки', () {
    test('запятая как разделитель', () {
      final result = _parsed(
        'Дата,Тип,Сумма,Категория\n4.10.2026,Расход,350.5,Кафе\n',
      );
      expect(result.errors, isEmpty);
      expect(result.rows.single.amount, Money.fromMinor(35050, 'RUB'));
    });

    test('без BOM и с переносом LF', () {
      final result = _parsed('$_header\n04.10.2026;Доход;100;Зарплата');
      expect(result.errors, isEmpty);
      expect(result.rows.single.type, TransactionType.income);
    });

    test('с BOM', () {
      final result = _parsed('\uFEFF$_header\r\n04.10.2026;Доход;100;Зарплата');
      expect(result.errors, isEmpty);
      expect(result.rows, hasLength(1));
    });

    test('заголовки без учёта регистра и пробелов, лишние колонки пропущены', () {
      final result = _parsed(
        ' дата ;ЛИШНЯЯ;ТИП;сумма;  Категория\r\n04.10.2026;x;расход;5;Кафе\r\n',
      );
      expect(result.errors, isEmpty);
      expect(result.rows.single.categoryName, 'Кафе');
    });

    test('не UTF-8', () {
      final bytes = [0xC4, 0xE0, 0xF2, 0xE0, 0x3B]; // «Дата;» в Windows-1251
      expect(
        parseCsvImport(bytes, clock: _clock),
        isA<CsvImportFileFailed>().having(
          (r) => r.failure,
          'failure',
          isA<CsvNotUtf8>(),
        ),
      );
    });

    test('пустой файл и один BOM', () {
      expect(_failureOf(''), isA<CsvEmptyFile>());
      expect(_failureOf('\uFEFF'), isA<CsvEmptyFile>());
    });

    test('битые кавычки', () {
      expect(
        _failureOf('$_header\r\n"04.10.2026;Расход;5;Кафе'),
        isA<CsvMalformed>(),
      );
    });

    test('нет обязательной колонки', () {
      final failure = _failureOf(
        'Дата;Тип;Категория\r\n04.10.2026;Расход;Кафе',
      );
      expect(failure, isA<CsvMissingColumns>());
      expect((failure as CsvMissingColumns).columns, ['Сумма']);
    });

    test('повтор заголовка', () {
      final failure = _failureOf('Дата;Тип;Сумма;Категория;сумма\r\n');
      expect(failure, isA<CsvDuplicateColumn>());
      expect((failure as CsvDuplicateColumn).column, 'Сумма');
    });

    test('пустые строки в конце пропускаются', () {
      final result = _parsed(
        '$_header\r\n04.10.2026;Расход;5;Кафе\r\n;;;\r\n\r\n',
      );
      expect(result.errors, isEmpty);
      expect(result.rows, hasLength(1));
    });
  });

  group('значения', () {
    test('дата: одна цифра допустима, 31.02 и 0 — нет, будущая — ошибка', () {
      expect(
        _parsed('$_header\r\n4.1.2026;Расход;5;Кафе').rows.single.day,
        DateOnly(2026, 1, 4),
      );
      expect(
        _errorsOf('31.02.2026;Расход;5;Кафе').single,
        isA<CsvInvalidDate>(),
      );
      expect(
        _errorsOf('2026-10-04;Расход;5;Кафе').single,
        isA<CsvInvalidDate>(),
      );
      expect(
        _errorsOf('08.10.2026;Расход;5;Кафе').single,
        isA<CsvFutureDate>(),
      );
      expect(_errorsOf('07.10.2026;Расход;5;Кафе'), isEmpty);
    });

    test('тип: регистр не важен, чужой — ошибка', () {
      expect(_errorsOf('04.10.2026;РАСХОД;5;Кафе'), isEmpty);
      final error = _errorsOf('04.10.2026;Перевод;5;Кафе').single;
      expect(error, isA<CsvInvalidType>());
      expect(error.value, 'Перевод');
    });

    test('сумма: ошибка берётся из parseAmount', () {
      final error = _errorsOf('04.10.2026;Расход;12.3.4;Кафе').single;
      expect(error, isA<CsvInvalidAmount>());
      expect(
        (error as CsvInvalidAmount).failure,
        AmountParseFailure.tooManySeparators,
      );
      expect(error.value, '12.3.4');
      expect(
        (_errorsOf('04.10.2026;Расход;;Кафе').single as CsvInvalidAmount)
            .failure,
        AmountParseFailure.empty,
      );
    });

    test('минус у расхода снимается, у дохода — ошибка', () {
      final row = _parsed('$_header\r\n04.10.2026;Расход;-350,00;Кафе')
          .rows
          .single;
      expect(row.amount, Money.fromMinor(35000, 'RUB'));
      expect(
        _errorsOf('04.10.2026;Доход;-350;Кафе').single,
        isA<CsvNegativeIncome>(),
      );
      expect(
        (_errorsOf('04.10.2026;Расход;--5;Кафе').single as CsvInvalidAmount)
            .failure,
        AmountParseFailure.negative,
      );
    });

    test('валюта: пусто — рубль, RUB и rub — можно, USD — ошибка', () {
      const header = 'Дата;Тип;Сумма;Валюта;Категория';
      expect(_parsed('$header\r\n04.10.2026;Расход;5;;Кафе').errors, isEmpty);
      expect(
        _parsed('$header\r\n04.10.2026;Расход;5;RUB;Кафе').errors,
        isEmpty,
      );
      expect(
        _parsed('$header\r\n04.10.2026;Расход;5;rub;Кафе').errors,
        isEmpty,
      );
      expect(
        _parsed('$header\r\n04.10.2026;Расход;5;USD;Кафе').errors.single,
        isA<CsvUnsupportedCurrency>(),
      );
    });

    test('лишние непустые ячейки — ошибка строки, а не угадывание', () {
      // Сумма с запятой без кавычек в файле с `,` расползается на 2 ячейки.
      const comma = 'Дата,Тип,Сумма,Категория,Подкатегория';
      final shifted = _parsed('$comma\r\n01.10.2026,Расход,350,50,Кафе,Кофе');
      expect(shifted.rows, isEmpty);
      final error = shifted.errors.single;
      expect(error, isA<CsvExtraCells>());
      expect(error.line, 2);
      expect(error.value, ',');

      final quoted = _parsed('$comma\r\n01.10.2026,Расход,"350,50",Кафе,Кофе');
      expect(quoted.errors, isEmpty);
      expect(quoted.rows.single.amount, Money.fromMinor(35050, 'RUB'));

      final semicolon = _errorsOf('04.10.2026;Расход;5;Кафе;в аэропорт');
      expect(semicolon.single, isA<CsvExtraCells>());
      expect(semicolon.single.value, ';');
    });

    test('пустые ячейки после последней колонки не мешают', () {
      final parsed = _parsed('$_header\r\n04.10.2026;Расход;5;Кафе;; \r\n');
      expect(parsed.errors, isEmpty);
      expect(parsed.rows, hasLength(1));
    });

    test('категория и подкатегория: пусто и длина 40', () {
      final ok = 'я' * 40;
      expect(_errorsOf('04.10.2026;Расход;5;$ok'), isEmpty);
      expect(
        _errorsOf('04.10.2026;Расход;5; ').single,
        isA<CsvEmptyCategory>(),
      );
      expect(
        _errorsOf('04.10.2026;Расход;5;${'я' * 41}').single,
        isA<CsvCategoryTooLong>(),
      );
      const header = 'Дата;Тип;Сумма;Категория;Подкатегория';
      expect(
        _parsed('$header\r\n04.10.2026;Расход;5;Кафе;${'я' * 41}')
            .errors
            .single,
        isA<CsvSubcategoryTooLong>(),
      );
      final row = _parsed('$header\r\n04.10.2026;Расход;5;Кафе; ').rows.single;
      expect(row.subcategoryName, isNull);
    });

    test('комментарий: trim, пусто — null, 200 можно, 201 — ошибка', () {
      const header = 'Дата;Тип;Сумма;Категория;Комментарий';
      expect(
        _parsed('$header\r\n04.10.2026;Расход;5;Кафе;  ').rows.single.note,
        isNull,
      );
      expect(
        _parsed('$header\r\n04.10.2026;Расход;5;Кафе; hi ').rows.single.note,
        'hi',
      );
      expect(
        _parsed('$header\r\n04.10.2026;Расход;5;Кафе;${'я' * 200}').errors,
        isEmpty,
      );
      expect(
        _parsed('$header\r\n04.10.2026;Расход;5;Кафе;${'я' * 201}')
            .errors
            .single,
        isA<CsvNoteTooLong>(),
      );
    });

    test('перенос внутри комментария не сбивает номер строки', () {
      const header = 'Дата;Тип;Сумма;Категория;Комментарий';
      final result = _parsed(
        '$header\r\n04.10.2026;Расход;5;Кафе;"а\r\nб\r\nв"\r\n04.10.2026;Расход;x;Кафе;\r\n',
      );
      expect(result.rows.single.line, 2);
      expect(result.errors.single.line, 3);
    });

    test('ID: плохой UUID и повтор ID операции', () {
      const header = 'Дата;Тип;Сумма;Категория;ID операции;ID категории';
      final bad = _parsed('$header\r\n04.10.2026;Расход;5;Кафе;123;')
          .errors
          .single;
      expect(bad, isA<CsvInvalidId>());
      expect((bad as CsvInvalidId).column, CsvIdColumn.transaction);

      final badCategory =
          _parsed('$header\r\n04.10.2026;Расход;5;Кафе;$_id1;oops')
                  .errors
                  .single
              as CsvInvalidId;
      expect(badCategory.column, CsvIdColumn.category);

      final dup = _parsed(
        '$header\r\n04.10.2026;Расход;5;Кафе;$_id1;\r\n04.10.2026;Расход;6;Кафе;$_id1;',
      );
      expect(dup.rows, hasLength(1));
      expect(dup.errors.single, isA<CsvDuplicateTransactionId>());
      expect(dup.errors.single.line, 3);
    });

    test(
      'время: подходящее берётся, чужое, пустое и испорченное — полдень дня',
      () {
        const header = 'Дата;Тип;Сумма;Категория;Время операции (UTC)';
        final noon = DateTime(2026, 10, 4, 12).toUtc();
        final good = DateTime.utc(2026, 10, 4, 12, 30);
        expect(
          _parsed(
            '$header\r\n04.10.2026;Расход;5;Кафе;${good.toIso8601String()}',
          ).rows.single.occurredAt,
          good,
        );
        for (final raw in [
          '',
          'вчера',
          '2026-10-04T12:30:00',
          '2026-01-01T12:00:00.000Z',
        ]) {
          final row = _parsed('$header\r\n04.10.2026;Расход;5;Кафе;$raw')
              .rows
              .single;
          expect(row.occurredAt, noon, reason: 'время "$raw"');
          expect(row.occurredAt.isUtc, isTrue);
        }
      },
    );

    test('сегодняшняя дата без времени — момент «сейчас»', () {
      final row = _parsed('$_header\r\n07.10.2026;Расход;5;Кафе').rows.single;
      expect(row.occurredAt, _now.toUtc());
    });

    test('несколько ошибок в одной строке собираются все', () {
      final errors = _errorsOf('32.01.2026;Займ;abc;');
      expect(errors.map((e) => e.runtimeType), [
        CsvInvalidDate,
        CsvInvalidType,
        CsvInvalidAmount,
        CsvEmptyCategory,
      ]);
    });
  });
}
