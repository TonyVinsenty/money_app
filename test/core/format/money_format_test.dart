import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/money/parse_amount.dart';

/// Превращает обычные пробелы шаблона в неразрывные (U+00A0). Так ожидаемые
/// строки в тестах читаются как текст, а настоящий код символа задан явно.
String nb(String template) =>
    template.replaceAll(' ', String.fromCharCode(0x00A0));

/// Настоящий минус U+2212.
final String minus = String.fromCharCode(0x2212);

Money rub(int minor) => Money.fromMinor(minor, 'RUB');

void main() {
  group('formatMoney: рубли', () {
    final cases = <int, String>{
      0: '0,00 ₽',
      1: '0,01 ₽',
      5: '0,05 ₽',
      99: '0,99 ₽',
      100: '1,00 ₽',
      123456: '1 234,56 ₽',
      1234567: '12 345,67 ₽',
      999999: '9 999,99 ₽',
      100000: '1 000,00 ₽',
      99900: '999,00 ₽',
    };
    cases.forEach((minor, expected) {
      test('$minor копеек -> $expected', () {
        expect(formatMoney(rub(minor)), nb(expected));
      });
    });

    test('предел ввода: 1 000 000 000 000 рублей целиком', () {
      expect(
        formatMoney(Money.fromMajorParts(1000000000000, 0, 'RUB')),
        nb('1 000 000 000 000,00 ₽'),
      );
    });

    test('разделитель разрядов и пробел перед валютой неразрывные', () {
      final text = formatMoney(rub(123456));
      expect(text, contains(String.fromCharCode(0x00A0)));
      // Обычных пробелов (U+0020) в результате нет вовсе.
      expect(text.contains(' '), isFalse);
    });
  });

  group('formatMoney: отрицательные суммы', () {
    test('минус 1 копейка', () {
      expect(formatMoney(rub(-1)), nb('${minus}0,01 ₽'));
    });

    test('минус 1 234,56', () {
      expect(formatMoney(rub(-123456)), nb('${minus}1 234,56 ₽'));
    });

    test('минус 1 234,50 (нулевая копейка сохраняется)', () {
      expect(formatMoney(rub(-123450)), nb('${minus}1 234,50 ₽'));
    });

    test('минус — юникодный U+2212, а не дефис', () {
      final text = formatMoney(rub(-100));
      expect(text.codeUnitAt(0), 0x2212);
      expect(text.contains('-'), isFalse);
    });

    test('положительная сумма без плюса', () {
      expect(formatMoney(rub(100)).startsWith('+'), isFalse);
    });

    test('без символа валюты', () {
      expect(
        formatMoney(rub(-123456), withCurrencySymbol: false),
        nb('${minus}1 234,56'),
      );
    });
  });

  group('formatMoney: валюты', () {
    test('USD -> доллар', () {
      expect(formatMoney(Money.fromMinor(123456, 'USD')), nb(r'1 234,56 $'));
    });

    test('EUR -> евро', () {
      expect(formatMoney(Money.fromMinor(123456, 'EUR')), nb('1 234,56 €'));
    });

    test('валюта не из каталога: нужна явная currency, иначе assert', () {
      final m = Money.fromMinor(123456, 'ABC');
      expect(() => formatMoney(m), throwsA(isA<AssertionError>()));
      expect(
        formatMoney(m, currency: currencyInfoFor('ABC', digits: 2)),
        nb('1 234,56 ABC'),
      );
    });
    test('GBP из каталога: символ £', () {
      expect(formatMoney(Money.fromMinor(123456, 'GBP')), nb('1 234,56 £'));
    });
    test('JPY без запятой, KWD с тремя знаками', () {
      expect(formatMoney(Money.fromMinor(1500, 'JPY')), nb('1 500 JPY'));
      expect(formatMoney(Money.fromMinor(12345, 'KWD')), nb('12,345 KWD'));
    });
  });

  group('currencySymbol', () {
    test('известные валюты — символ, неизвестная — сам код', () {
      expect(currencySymbol('RUB'), '₽');
      expect(currencySymbol('USD'), r'$');
      expect(currencySymbol('EUR'), '€');
      expect(currencySymbol('ABC'), 'ABC');
    });
  });

  group('formatMoney: без символа валюты', () {
    test('только число', () {
      expect(
        formatMoney(rub(1234567), withCurrencySymbol: false),
        nb('12 345,67'),
      );
    });

    test('ноль', () {
      expect(formatMoney(rub(0), withCurrencySymbol: false), '0,00');
    });
  });

  group('formatMoney: точность на больших значениях', () {
    test('2^53 + 1 рублей (первое целое, которое не помещается в дробное)', () {
      expect(
        formatMoney(Money.fromMajorParts(9007199254740993, 0, 'RUB')),
        nb('9 007 199 254 740 993,00 ₽'),
      );
    });

    test('2^53 + 1 копеек', () {
      expect(formatMoney(rub(9007199254740993)), nb('90 071 992 547 409,93 ₽'));
    });

    test('максимальное значение Money', () {
      expect(
        formatMoney(rub(9223372036854775807)),
        nb('92 233 720 368 547 758,07 ₽'),
      );
    });

    test('минимальное значение int (без переполнения при взятии модуля)', () {
      expect(
        formatMoney(rub(-9223372036854775808)),
        nb('${minus}92 233 720 368 547 758,08 ₽'),
      );
    });
  });

  group('formatMoney и parseAmount: обратный путь', () {
    final minors = <int>[0, 1, 5, 99, 100, 123456, 1234567, 100000000000000];
    for (final minor in minors) {
      test('$minor копеек: формат без символа разбирается обратно', () {
        final text = formatMoney(rub(minor), withCurrencySymbol: false);
        switch (parseAmount(text)) {
          case AmountParsed(:final amount):
            expect(amount, rub(minor));
          case AmountParseFailed(:final failure):
            fail('«$text» не разобралось: $failure');
        }
      });
    }
  });

  group('formatMoney: валюты каталога и свои (ADR 0010, п. 16.5)', () {
    Money m(int minor, String code) => Money.fromMinor(minor, code);

    test('обычная валюта — все знаки', () {
      expect(formatMoney(m(15000, 'USD')), nb(r'150,00 $'));
    });

    test('крипта: нули срезаются, но не меньше двух знаков', () {
      expect(formatMoney(m(150000, 'BTC')), nb('0,0015 BTC'));
      expect(formatMoney(m(100000000, 'BTC')), nb('1,00 BTC'));
      expect(formatMoney(m(-50000000, 'ETH')), nb('${minus}0,50 ETH'));
      expect(formatMoney(m(1, 'BTC')), nb('0,00000001 BTC'));
    });

    test('10^14 единиц USDT', () {
      expect(formatMoney(m(100000000000000, 'USDT')), nb('1 000 000,00 USDT'));
    });

    test('своя валюта: 0 знаков — без запятой', () {
      final abc = currencyInfoFor('ABC', digits: 0);
      expect(formatMoney(m(1500, 'ABC'), currency: abc), nb('1 500 ABC'));
    });

    test('своя валюта: 4 знака', () {
      final abc = currencyInfoFor('ABC', digits: 4);
      expect(formatMoney(m(125000, 'ABC'), currency: abc), nb('12,50 ABC'));
      expect(formatMoney(m(1, 'ABC'), currency: abc), nb('0,0001 ABC'));
    });

    test('без символа — только число', () {
      expect(
        formatMoney(m(150000, 'BTC'), withCurrencySymbol: false),
        '0,0015',
      );
    });

    test('currencySymbol берёт символ из каталога', () {
      expect(currencySymbol('CNY'), '¥');
      expect(currencySymbol('BTC'), 'BTC');
    });
  });
}
