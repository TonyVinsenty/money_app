import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/money/parse_amount.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/csv_import/domain/csv_import_failures.dart';
import 'package:money_app/features/csv_import/domain/parse_csv_import.dart';

import '../../../support/fixed_clock.dart';

// Разбор CSV v2 (шаг 5.17): счета, начальный остаток, значки, валюты.

final _clock = FixedClock(DateTime(2026, 10, 7, 9, 30));
const _acc1 = '0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeea1';

const _header =
    'Дата;Тип;Сумма;Валюта;Категория;Подкатегория;Счёт;ID счёта;'
    'Значок категории;Значок подкатегории';

CsvImportParsed _parsed(String rows, {String header = _header}) {
  final result = parseCsvImport(
    utf8.encode('$header\r\n$rows\r\n'),
    clock: _clock,
  );
  expect(result, isA<CsvImportParsed>());
  return result as CsvImportParsed;
}

List<CsvRowError> _errors(String rows, {String header = _header}) =>
    _parsed(rows, header: header).errors;

CsvInvalidAmount _amountError(String rows) =>
    _errors(rows).single as CsvInvalidAmount;

void main() {
  group('счёт и значки у дохода и расхода', () {
    test('колонки попали в строку, пробелы по краям срезаны', () {
      final row = _parsed(
        '04.10.2026;Расход;5;;Кафе;Кофе; Карта ;$_acc1; local_cafe ; glyph:Ж ',
      ).rows.single;
      expect(row.accountName, 'Карта');
      expect(row.accountId, _acc1);
      expect(row.categoryIconKey, 'local_cafe');
      expect(row.subcategoryIconKey, 'glyph:Ж');
    });

    test('пустые ячейки и нет колонок — значков и счёта нет', () {
      final empty = _parsed('04.10.2026;Расход;5;;Кафе;;;;;').rows.single;
      expect(empty.accountName, isNull);
      expect(empty.accountId, isNull);
      expect(empty.categoryIconKey, isNull);
      expect(empty.subcategoryIconKey, isNull);

      final old = _parsed(
        '04.10.2026;Расход;5;Кафе',
        header: 'Дата;Тип;Сумма;Категория',
      ).rows.single;
      expect(old.accountName, isNull);
      expect(old.categoryIconKey, isNull);
    });

    test('значок любого вида ошибки не даёт', () {
      final result = _parsed(
        '04.10.2026;Расход;5;;Кафе;;;;no_such_icon;${'я' * 500}',
      );
      expect(result.errors, isEmpty);
      expect(result.rows, hasLength(1));
    });

    test('счёт длиннее 40 — ошибка, ровно 40 можно', () {
      expect(_errors('04.10.2026;Расход;5;;Кафе;;${'я' * 40};;;'), isEmpty);
      final error = _errors('04.10.2026;Расход;5;;Кафе;;${'я' * 41};;;');
      expect(error.single, isA<CsvAccountTooLong>());
    });

    test('плохой ID счёта — ошибка с колонкой счёта', () {
      final error = _errors('04.10.2026;Расход;5;;Кафе;;Карта;oops;;').single;
      expect(error, isA<CsvInvalidId>());
      expect((error as CsvInvalidId).column, CsvIdColumn.account);
      expect(error.value, 'oops');
    });
  });

  group('начальный остаток', () {
    test('счёт, дата, остаток и id; регистр типа не важен', () {
      final result = _parsed(
        '01.09.2026;НАЧАЛЬНЫЙ остаток;12000,50;;;;Карта;$_acc1;;',
      );
      expect(result.errors, isEmpty);
      expect(result.rows, isEmpty);
      final balance = result.openingBalances.single;
      expect(balance.line, 2);
      expect(balance.day, DateOnly(2026, 9, 1));
      expect(balance.accountName, 'Карта');
      expect(balance.accountId, _acc1);
      expect(balance.amount, Money.fromMinor(1200050, 'RUB'));
      expect(balance.customDigits, isNull);
    });

    test('минус разрешён (обычный и юникодный), ноль можно', () {
      final minus = String.fromCharCode(0x2212);
      final result = _parsed(
        '01.09.2026;Начальный остаток;-1500,00;;;;Долг;;;\r\n'
        '01.09.2026;Начальный остаток;${minus}2;;;;Долг2;;;\r\n'
        '01.09.2026;Начальный остаток;0;;;;Ноль;;;',
      );
      expect(result.errors, isEmpty);
      expect(result.openingBalances.map((b) => b.amount.minorUnits), [
        -150000,
        -200,
        0,
      ]);
    });

    test('без счёта — ошибка, даже если есть ID счёта', () {
      final error = _errors('01.09.2026;Начальный остаток;5;;;;;$_acc1;;');
      expect(error.single, isA<CsvOpeningBalanceNoAccount>());
      // Нет самой колонки «Счёт» — то же самое.
      expect(
        _errors(
          '01.09.2026;Начальный остаток;5',
          header: 'Дата;Тип;Сумма;Категория',
        ).single,
        isA<CsvOpeningBalanceNoAccount>(),
      );
    });

    test('категория не пуста — ошибка со значением', () {
      final error = _errors('01.09.2026;Начальный остаток;5;;Кафе;;Карта;;;');
      expect(error.single, isA<CsvOpeningBalanceWithCategory>());
      expect(error.single.value, 'Кафе');
    });

    test('имя счёта длиннее 40 и плохой ID счёта', () {
      expect(
        _errors('01.09.2026;Начальный остаток;5;;;;${'я' * 41};;;').single,
        isA<CsvAccountTooLong>(),
      );
      final error = _errors('01.09.2026;Начальный остаток;5;;;;Карта;42;;');
      expect((error.single as CsvInvalidId).column, CsvIdColumn.account);
    });

    test('значки у начального остатка игнорируются, не ошибка', () {
      final result = _parsed(
        '01.09.2026;Начальный остаток;5;;;;Карта;;local_cafe;glyph:Ж',
      );
      expect(result.errors, isEmpty);
      expect(result.openingBalances, hasLength(1));
    });

    test('дата: будущая и неверная — ошибки, момент из файла берётся', () {
      expect(
        _errors('08.10.2026;Начальный остаток;5;;;;Карта;;;').single,
        isA<CsvFutureDate>(),
      );
      expect(
        _errors('31.02.2026;Начальный остаток;5;;;;Карта;;;').single,
        isA<CsvInvalidDate>(),
      );
      const header = 'Дата;Тип;Сумма;Категория;Счёт;Время операции (UTC)';
      final moment = DateTime.utc(2026, 9, 1, 7, 15);
      final balance = _parsed(
        '01.09.2026;Начальный остаток;5;;Карта;${moment.toIso8601String()}',
        header: header,
      ).openingBalances.single;
      expect(balance.occurredAt, moment);
    });

    test('разделитель запятая', () {
      final result = parseCsvImport(
        utf8.encode(
          'Дата,Тип,Сумма,Категория,Счёт\n'
          '01.09.2026,Начальный остаток,"1500,50",,Карта\n',
        ),
        clock: _clock,
      );
      final parsed = result as CsvImportParsed;
      expect(parsed.errors, isEmpty);
      expect(parsed.openingBalances.single.amount.minorUnits, 150050);
    });
  });

  group('валюты', () {
    test('расход в USD и JPY — по знакам валюты, регистр кода не важен', () {
      final usd = _parsed('04.10.2026;Расход;-12,50;usd;Кафе;;;;;').rows.single;
      expect(usd.amount, Money.fromMinor(1250, 'USD'));
      final yen = _parsed('04.10.2026;Расход;1500;JPY;Кафе;;;;;').rows.single;
      expect(yen.amount, Money.fromMinor(1500, 'JPY'));
    });

    test('у иены цифры после запятой — ошибка с валютой и знаками', () {
      final error = _amountError('04.10.2026;Расход;1,5;JPY;Кафе;;;;;');
      expect(error.failure, AmountParseFailure.tooManyDecimals);
      expect(error.currencyCode, 'JPY');
      expect(error.currencyDigits, 0);
      expect(error.digitsFromFile, isFalse);
    });

    test('у расхода и дохода крипта, своя валюта и мусор — ошибка', () {
      for (final code in ['USDT', 'BTC', 'ABC', 'US-D', 'XYZ']) {
        final errors = _errors('04.10.2026;Доход;5;$code;Кафе;;;;;');
        expect(errors.single, isA<CsvUnsupportedCurrency>(), reason: code);
        expect(errors.single.value, code);
      }
    });

    test('слишком большая сумма расхода: ошибка несёт RUB и 2 знака', () {
      final error = _amountError('01.09.2026;Расход;1000000000001;;Кафе;;;;;');
      expect(error.failure, AmountParseFailure.tooLarge);
      expect(error.currencyCode, 'RUB');
    });

    test('начальный остаток: пусто — RUB, код каталога, крипта', () {
      final result = _parsed(
        '01.09.2026;Начальный остаток;1;;;;A;;;\r\n'
        '01.09.2026;Начальный остаток;-5;usd;;;B;;;\r\n'
        '01.09.2026;Начальный остаток;0,00150000;BTC;;;C;;;\r\n'
        '01.09.2026;Начальный остаток;100;JPY;;;D;;;',
      );
      expect(result.errors, isEmpty);
      final b = result.openingBalances;
      expect(b[0].amount, Money.fromMinor(100, 'RUB'));
      expect(b[1].amount, Money.fromMinor(-500, 'USD'));
      expect(b[2].amount, Money.fromMinor(150000, 'BTC'));
      expect(b[3].amount, Money.fromMinor(100, 'JPY'));
      expect(b.map((e) => e.customDigits), everyElement(isNull));
    });

    test('начальный остаток в своей валюте: знаки — из суммы', () {
      final result = _parsed(
        '01.09.2026;Начальный остаток;12,3456;ABC;;;A;;;\r\n'
        '01.09.2026;Начальный остаток;-7;abc;;;B;;;\r\n'
        '01.09.2026;Начальный остаток;0,12345678;XYZ12;;;C;;;\r\n'
        '01.09.2026;Начальный остаток;5,;ABC;;;D;;;',
      );
      expect(result.errors, isEmpty);
      final b = result.openingBalances;
      expect(b[0].amount, Money.fromMinor(123456, 'ABC'));
      expect(b[0].customDigits, 4);
      expect(b[1].amount, Money.fromMinor(-7, 'ABC'));
      expect(b[1].customDigits, 0);
      expect(b[2].amount, Money.fromMinor(12345678, 'XYZ12'));
      expect(b[2].customDigits, 8);
      expect(b[3].customDigits, 0);
    });

    test('9 цифр после запятой у своей валюты — ошибка', () {
      final error = _amountError(
        '01.09.2026;Начальный остаток;0,123456789;ABC;;;A;;;',
      );
      expect(error.failure, AmountParseFailure.tooManyDecimals);
      expect(error.digitsFromFile, isTrue);
      expect(error.currencyDigits, 8);
    });

    test('плохой код валюты у начального остатка — ошибка', () {
      for (final code in ['US-D', 'US', '1AB', 'ABCDEFGHIJK']) {
        final errors = _errors('01.09.2026;Начальный остаток;5;$code;;;A;;;');
        expect(errors.single, isA<CsvInvalidCurrencyCode>(), reason: code);
        expect(errors.single.value, code);
      }
    });

    test('предел суммы у каталожной валюты несёт её знаки', () {
      final error = _amountError(
        '01.09.2026;Начальный остаток;1000001;BTC;;;A;;;',
      );
      expect(error.failure, AmountParseFailure.tooLarge);
      expect(error.currencyCode, 'BTC');
      expect(error.currencyDigits, 8);
    });
  });
}
