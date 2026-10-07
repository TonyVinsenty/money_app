import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/csv/csv_codec.dart';

/// Ошибка разбора: тип FormatException и текст с нужным номером строки.
Matcher _formatErrorAtLine(int line) => throwsA(
  isA<FormatException>().having(
    (e) => e.message,
    'message',
    contains('строке $line'),
  ),
);

void main() {
  group('encodeCsv: экранирование полей (RFC 4180)', () {
    test('поле с разделителем ; берётся в кавычки', () {
      expect(
        encodeCsv([
          ['еда; быт'],
        ]),
        '\uFEFF"еда; быт"\r\n',
      );
    });

    test('поле с кавычкой берётся в кавычки, а кавычка удваивается', () {
      expect(
        encodeCsv([
          ['он "да"'],
        ]),
        '\uFEFF"он ""да"""\r\n',
      );
    });

    test('поле с \\n и с \\r\\n берётся в кавычки', () {
      expect(
        encodeCsv([
          ['a\nb'],
          ['c\r\nd'],
        ]),
        '\uFEFF"a\nb"\r\n"c\r\nd"\r\n',
      );
    });

    test('обычные поля пишутся без кавычек', () {
      expect(
        encodeCsv([
          ['Продукты', '350,00'],
        ]),
        '\uFEFFПродукты;350,00\r\n',
      );
    });

    test('пустое поле пишется пустой строкой без кавычек', () {
      expect(
        encodeCsv([
          ['a', '', 'c'],
          [''],
        ]),
        '\uFEFFa;;c\r\n\r\n',
      );
    });

    test('пустой список строк даёт только BOM', () {
      expect(encodeCsv([]), '\uFEFF');
    });

    test('строка без полей запрещена', () {
      expect(() => encodeCsv([[]]), throwsArgumentError);
    });
  });

  group('encodeCsv: BOM и окончания строк', () {
    test('в начале ровно один BOM', () {
      final encoded = encodeCsv([
        ['x'],
      ]);
      expect(encoded.startsWith('\uFEFF'), isTrue);
      expect(encoded.split('\uFEFF'), hasLength(2));
    });

    test('строки разделяются \\r\\n, голых \\n нет', () {
      final encoded = encodeCsv([
        ['a'],
        ['b'],
        ['d'],
      ]);
      expect(RegExp(r'(?<!\r)\n').hasMatch(encoded), isFalse);
      expect(encoded, contains('\r\n'));
    });
  });

  group('decodeCsv: базовое чтение', () {
    test('BOM снимается, а без BOM декодер тоже работает', () {
      expect(decodeCsv('\uFEFFa;b\r\n'), [
        ['a', 'b'],
      ]);
      expect(decodeCsv('a;b\r\n'), [
        ['a', 'b'],
      ]);
    });

    test('\\n и \\r\\n читаются одинаково', () {
      const lf = 'a;"b\nc"\nd;e\n';
      const crlf = 'a;"b\nc"\r\nd;e\r\n';
      const expected = [
        ['a', 'b\nc'],
        ['d', 'e'],
      ];
      expect(decodeCsv(lf), expected);
      expect(decodeCsv(crlf), expected);
    });

    test('пустые поля и пустой текст', () {
      expect(decodeCsv('a;;c\r\n;\r\n'), [
        ['a', '', 'c'],
        ['', ''],
      ]);
      expect(decodeCsv(''), isEmpty);
    });

    test('последняя строка без переноса читается', () {
      expect(decodeCsv('a;b'), [
        ['a', 'b'],
      ]);
    });

    test('точка с запятой в конце строки даёт пустое последнее поле', () {
      expect(decodeCsv('a;'), [
        ['a', ''],
      ]);
    });
  });

  group('туда-обратно', () {
    test('кириллица и эмодзи (флаг) не теряются', () {
      final rows = [
        ['Категория', 'Смайлик'],
        ['Продукты', '\u{1F1F7}\u{1F1FA}'],
      ];
      expect(decodeCsv(encodeCsv(rows)), rows);
    });

    test('сложный набор: кавычки, разделители, переносы, пустые поля', () {
      final rows = [
        ['Дата', 'Категория', 'Сумма', 'Комментарий'],
        ['2026-10-01', 'Еда; быт', '350', 'Продукты "Пятёрочка"'],
        ['2026-10-02', 'Дом', '1200', 'строка1\nстрока2'],
        ['2026-10-03', 'Транспорт', '45', 'Windows\r\nстиль'],
        ['', '', '', ''],
        ['x', '', 'y', ''],
        [''],
        ['"', ',', '""', '\u{1F1F7}\u{1F1FA}'],
        ['Длинная', List.filled(300, 'слово').join(' ')],
      ];
      expect(decodeCsv(encodeCsv(rows)), rows);
    });
  });

  group('decodeCsv: ошибки на некорректном вводе', () {
    test('незакрытая кавычка в конце файла', () {
      expect(() => decodeCsv('a;"незакрытое'), throwsFormatException);
    });

    test('ошибка незакрытой кавычки содержит номер строки', () {
      expect(() => decodeCsv('a;b\r\nc;"x\r\ny'), _formatErrorAtLine(2));
    });

    test('символ после закрывающей кавычки', () {
      expect(() => decodeCsv('"ab"x;c'), throwsFormatException);
    });

    test('ошибка после закрывающей кавычки содержит номер строки', () {
      expect(() => decodeCsv('a;b\r\n"c"d\r\n'), _formatErrorAtLine(2));
    });

    test('кавычка внутри поля без кавычек', () {
      expect(() => decodeCsv('ab"c;d'), throwsFormatException);
    });

    test('одиночный \\r без \\n', () {
      expect(() => decodeCsv('a\rb'), throwsFormatException);
    });
  });

  group('decodeCsv: разделитель-запятая', () {
    test('читает поля через запятую', () {
      expect(decodeCsv('a,b\r\nc,d', separator: ','), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    test('точка с запятой при запятой — обычный символ', () {
      expect(decodeCsv('a;b,c', separator: ','), [
        ['a;b', 'c'],
      ]);
    });

    test('запятая в кавычках остаётся в поле', () {
      expect(decodeCsv('"a,b",c', separator: ','), [
        ['a,b', 'c'],
      ]);
    });

    test('символ после закрывающей кавычки — ошибка', () {
      expect(() => decodeCsv('"a"x,b', separator: ','), throwsFormatException);
    });

    test('разделитель по умолчанию — ;, чужой разделитель — ArgumentError', () {
      expect(decodeCsv('a,b;c'), [
        ['a,b', 'c'],
      ]);
      expect(() => decodeCsv('a', separator: '|'), throwsArgumentError);
    });
  });
}
