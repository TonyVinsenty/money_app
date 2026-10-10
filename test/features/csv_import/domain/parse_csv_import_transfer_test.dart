import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/csv_import/domain/csv_import_failures.dart';
import 'package:money_app/features/csv_import/domain/parse_csv_import.dart';
import 'package:money_app/features/csv_import/presentation/csv_import_texts.dart';

import '../../../support/fixed_clock.dart';

// Разбор строк `Перевод` (шаг 5.24): только строки в модель, без плана.

final _clock = FixedClock(DateTime(2026, 10, 7, 9, 30));
const _id1 = '0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeea1';
const _id2 = '0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeea2';
const _tid = '0199aaaa-bbbb-7ccc-8ddd-eeeeeeeeeeb1';

const _header =
    'Дата;Тип;Сумма;Валюта;Категория;Подкатегория;Комментарий;Счёт;'
    'Счёт зачисления;ID операции;ID счёта;ID счёта зачисления';

CsvImportParsed _parsed(String rows) {
  final result = parseCsvImport(
    utf8.encode('$_header\r\n$rows\r\n'),
    clock: _clock,
  );
  expect(result, isA<CsvImportParsed>());
  return result as CsvImportParsed;
}

/// Единственная ошибка строки и её полный текст.
String _error(String rows) {
  final parsed = _parsed(rows);
  expect(parsed.transfers, isEmpty);
  expect(parsed.errors, hasLength(1));
  return csvRowErrorMessage(parsed.errors.single);
}

void main() {
  _sameNameGroup();
  test('корректный перевод разбирается в ParsedTransfer', () {
    final parsed = _parsed(
      '04.10.2026;Перевод;1500,50;;;;Снял;Карта;Наличные;$_tid;$_id1;$_id2',
    );
    expect(parsed.errors, isEmpty);
    expect(parsed.rows, isEmpty);
    final t = parsed.transfers.single;
    expect(t.line, 2);
    expect(t.day, DateOnly(2026, 10, 4));
    expect(t.amount, Money.fromMinor(150050, 'RUB'));
    expect(t.fromAccountName, 'Карта');
    expect(t.toAccountName, 'Наличные');
    expect(t.fromAccountId, _id1);
    expect(t.toAccountId, _id2);
    expect(t.transferId, _tid);
    expect(t.note, 'Снял');
    expect(t.customDigits, isNull);
  });

  test('счёт можно задать только ID; тип без учёта регистра', () {
    final t = _parsed('04.10.2026;ПЕРЕВОД;5;USD;;;;;;;$_id1;$_id2')
        .transfers
        .single;
    expect(t.fromAccountName, isNull);
    expect(t.toAccountName, isNull);
    expect(t.amount, Money.fromMinor(500, 'USD'));
  });

  test('BTC и своя валюта: знаки по валюте', () {
    final btc = _parsed('04.10.2026;Перевод;0,00150000;BTC;;;;A;B;;;')
        .transfers
        .single;
    expect(btc.amount, Money.fromMinor(150000, 'BTC'));
    final own = _parsed('04.10.2026;Перевод;12,3456;ABC;;;;A;B;;;')
        .transfers
        .single;
    expect(own.amount, Money.fromMinor(123456, 'ABC'));
    expect(own.customDigits, 4);
  });

  group('ошибки строки', () {
    test('не указан счёт', () {
      expect(
        _error('04.10.2026;Перевод;5;;;;;;Наличные;;;'),
        'Строка 2: у перевода не указан счёт',
      );
    });

    test('не указан счёт зачисления', () {
      expect(
        _error('04.10.2026;Перевод;5;;;;;Карта;;;;'),
        'Строка 2: у перевода не указан счёт зачисления',
      );
    });

    test('счета совпадают по имени (без учёта регистра) и по ID', () {
      const text = 'Строка 2: у перевода счёт и счёт зачисления совпадают';
      expect(_error('04.10.2026;Перевод;5;;;;;Карта;карта;;;'), text);
      expect(_error('04.10.2026;Перевод;5;;;;;;;;$_id1;$_id1'), text);
    });

    test('сумма 0', () {
      expect(
        _error('04.10.2026;Перевод;0,00;;;;;A;B;;;'),
        'Строка 2: сумма «0,00» — у перевода нужна сумма больше нуля',
      );
    });

    test('минус — прежний текст', () {
      expect(
        _error('04.10.2026;Перевод;-5;;;;;A;B;;;'),
        'Строка 2: сумма «-5» — минус можно ставить только у расхода и '
        'начального остатка',
      );
    });

    test('категория не пуста', () {
      expect(
        _error('04.10.2026;Перевод;5;;Кафе;;;A;B;;;'),
        'Строка 2: у перевода категория «Кафе» — ячейка должна быть пустой. '
        'Похоже, колонки съехали',
      );
    });

    test('пустая сумма и испорченный ID счёта зачисления', () {
      expect(
        _error('04.10.2026;Перевод;;;;;;A;B;;;'),
        'Строка 2: не указана сумма',
      );
      expect(
        _error('04.10.2026;Перевод;5;;;;;A;B;;;oops'),
        'Строка 2: в колонке «ID счёта зачисления» не ID. Очистите эту ячейку',
      );
    });

    test('повтор ID операции среди переводов', () {
      final parsed = _parsed(
        '04.10.2026;Перевод;5;;;;;A;B;$_tid;;\r\n'
        '05.10.2026;Перевод;6;;;;;A;B;$_tid;;',
      );
      expect(parsed.transfers, hasLength(1));
      expect(parsed.errors.single, isA<CsvDuplicateTransactionId>());
    });
  });

  test('неизвестный тип называет «Перевод»', () {
    final parsed = _parsed('04.10.2026;Обмен;5;;Кафе;;;;;;;');
    expect(
      csvRowErrorMessage(parsed.errors.single),
      'Строка 2: тип «Обмен» — нужен «Расход», «Доход», '
      '«Начальный остаток» или «Перевод»',
    );
  });
}

void _sameNameGroup() {
  group('одинаковые имена при разных ID (5.25b)', () {
    test('оба ID есть и разные: не ошибка, план разберётся', () {
      final parsed = _parsed(
        '04.10.2026;Перевод;5;;;;;Карта;Карта;;$_id1;$_id2',
      );
      expect(parsed.errors, isEmpty);
      expect(parsed.transfers, hasLength(1));
    });

    test('ID нет хотя бы у одного счёта: имена совпадают - ошибка', () {
      final parsed = _parsed('04.10.2026;Перевод;5;;;;;Карта;карта;;$_id1;');
      expect(parsed.errors.single, isA<CsvTransferSameAccount>());
    });
  });
}
