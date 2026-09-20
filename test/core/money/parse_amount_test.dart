import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/money/parse_amount.dart';

/// Ждёт успех и возвращает сумму; иначе тест падает с понятным сообщением.
Money expectParsed(String input, {String currency = 'RUB'}) {
  final result = parseAmount(input, currency: currency);
  switch (result) {
    case AmountParsed(:final amount):
      return amount;
    case AmountParseFailed(:final failure):
      fail('«$input» должно разобраться, а получили $failure');
  }
}

/// Ждёт отказ и возвращает его причину.
AmountParseFailure expectFailed(String input) {
  final result = parseAmount(input);
  switch (result) {
    case AmountParsed(:final amount):
      fail('«$input» должно быть ошибкой, а получили $amount');
    case AmountParseFailed(:final failure):
      return failure;
  }
}

void main() {
  group('успешные разборы', () {
    const cases = <String, int>{
      '7': 700,
      '1234.5': 123450,
      ',5': 50,
      '5,': 500,
      '1,50': 150,
      '1.5': 150,
      '0,05': 5,
      '0': 0,
      '0,00': 0,
      ',0': 0,
      '00012,3': 1230,
    };
    cases.forEach((input, minor) {
      test('«$input» даёт $minor коп.', () {
        expect(expectParsed(input), Money.fromMinor(minor, 'RUB'));
      });
    });

    test('обычный пробел как разделитель тысяч', () {
      expect(expectParsed('12 345,67').minorUnits, 1234567);
    });

    test('неразрывный пробел U+00A0', () {
      expect(expectParsed('12\u00A0345,67').minorUnits, 1234567);
    });

    test('узкий неразрывный пробел U+202F', () {
      expect(expectParsed('12\u202F345,67').minorUnits, 1234567);
    });

    test('пробелы по краям и перевод строки в конце', () {
      expect(expectParsed('  5  ').minorUnits, 500);
      expect(expectParsed('5\n').minorUnits, 500);
      expect(expectParsed('\t5,5\r\n').minorUnits, 550);
    });

    test('валюта по умолчанию — рубль', () {
      expect(expectParsed('1').currency, 'RUB');
    });

    test('параметр currency попадает в Money', () {
      final amount = expectParsed('10,5', currency: 'USD');
      expect(amount, Money.fromMinor(1050, 'USD'));
      expect(amount.currency, 'USD');
    });

    test('результат всегда неотрицательный', () {
      for (final input in ['0', '0,01', '7', '1 000', '999999,99']) {
        expect(expectParsed(input).isNegative, isFalse, reason: input);
      }
    });
  });

  group('верхний предел', () {
    test('ровно предел проходит', () {
      expect(expectParsed('1000000000000').minorUnits, 100000000000000);
      expect(expectParsed('1 000 000 000 000,00').minorUnits, 100000000000000);
    });

    test('константа предела — триллион', () {
      expect(maxInputMajorUnits, 1000000000000);
    });

    test('предел плюс копейка — слишком большая сумма', () {
      expect(expectFailed('1000000000000,01'), AmountParseFailure.tooLarge);
      expect(expectFailed('1000000000001'), AmountParseFailure.tooLarge);
    });

    test('огромное число не бросает исключение', () {
      expect(expectFailed('99999999999999999999'), AmountParseFailure.tooLarge);
      expect(expectFailed('9' * 500), AmountParseFailure.tooLarge);
    });
  });

  group('ошибки', () {
    test('пусто', () {
      expect(expectFailed(''), AmountParseFailure.empty);
      expect(expectFailed('   '), AmountParseFailure.empty);
      expect(expectFailed('\u00A0\u202F\n'), AmountParseFailure.empty);
    });

    test('не число', () {
      for (final input in [
        'abc',
        '1e5',
        '+5',
        '5 ₽',
        '\u0663', // арабская цифра три
        ',',
        '.',
        '5-3',
        '1a',
      ]) {
        expect(
          expectFailed(input),
          AmountParseFailure.notANumber,
          reason: input,
        );
      }
    });

    test('минус', () {
      expect(expectFailed('-100'), AmountParseFailure.negative);
      expect(expectFailed('\u2212100'), AmountParseFailure.negative);
      expect(expectFailed('-0'), AmountParseFailure.negative);
      expect(expectFailed(' - 5'), AmountParseFailure.negative);
      expect(expectFailed('-'), AmountParseFailure.negative);
    });

    test('минус с мусором — это не число', () {
      expect(expectFailed('-abc'), AmountParseFailure.notANumber);
      expect(expectFailed('--5'), AmountParseFailure.notANumber);
    });

    test('минус важнее прочих ошибок числа', () {
      expect(expectFailed('-1,2,3'), AmountParseFailure.negative);
      expect(expectFailed('-1,234'), AmountParseFailure.negative);
    });

    test('слишком много разделителей', () {
      for (final input in ['1,2,3', '1,234,567', '1.234,56', '1..2']) {
        expect(
          expectFailed(input),
          AmountParseFailure.tooManySeparators,
          reason: input,
        );
      }
    });

    test('слишком много знаков после запятой', () {
      for (final input in ['1.234', '5,123', '0,001', '1,500']) {
        expect(
          expectFailed(input),
          AmountParseFailure.tooManyDecimals,
          reason: input,
        );
      }
    });

    test('много разделителей важнее многих знаков', () {
      expect(expectFailed('1,234,5'), AmountParseFailure.tooManySeparators);
    });

    test('лишние знаки важнее предела', () {
      expect(
        expectFailed('99999999999999999999,123'),
        AmountParseFailure.tooManyDecimals,
      );
    });
  });
}
