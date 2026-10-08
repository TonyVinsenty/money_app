import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/money/parse_amount.dart';

AmountParseResult _parse(String input, String code, {int? digits}) =>
    parseAmount(
      input,
      currency: code,
      currencyInfo: currencyInfoFor(code, digits: digits),
    );

int _minor(AmountParseResult result) {
  expect(result, isA<AmountParsed>());
  return (result as AmountParsed).amount.minorUnits;
}

AmountParseFailure _failure(AmountParseResult result) {
  expect(result, isA<AmountParseFailed>());
  return (result as AmountParseFailed).failure;
}

void main() {
  test('предел: 10^14 минимальных единиц, для рубля прежний триллион', () {
    expect(maxInputMinorUnits, 100000000000000);
    expect(maxInputMajorUnits * 100, maxInputMinorUnits);
  });

  group('BTC (8 знаков)', () {
    test('0,00000001 это 1 единица', () {
      expect(_minor(_parse('0,00000001', 'BTC')), 1);
    });
    test('9 знаков это tooManyDecimals', () {
      expect(
        _failure(_parse('0,000000011', 'BTC')),
        AmountParseFailure.tooManyDecimals,
      );
    });
    test('1 000 000 можно, 1 000 000,00000001 нельзя', () {
      expect(_minor(_parse('1 000 000', 'BTC')), maxInputMinorUnits);
      expect(
        _failure(_parse('1000000,00000001', 'BTC')),
        AmountParseFailure.tooLarge,
      );
    });
    test('результат остаётся в BTC', () {
      final result = _parse('1,5', 'BTC') as AmountParsed;
      expect(result.amount, Money.fromMinor(150000000, 'BTC'));
    });
  });

  group('JPY (0 знаков)', () {
    test('1500 можно', () => expect(_minor(_parse('1500', 'JPY')), 1500));
    test('1500,5 это tooManyDecimals', () {
      expect(
        _failure(_parse('1500,5', 'JPY')),
        AmountParseFailure.tooManyDecimals,
      );
    });
    test('предел 10^14 иен', () {
      expect(_minor(_parse('100000000000000', 'JPY')), maxInputMinorUnits);
      expect(
        _failure(_parse('100000000000001', 'JPY')),
        AmountParseFailure.tooLarge,
      );
    });
  });

  test('KWD: 3 знака', () {
    expect(_minor(_parse('1,234', 'KWD')), 1234);
    expect(
      _failure(_parse('1,2345', 'KWD')),
      AmountParseFailure.tooManyDecimals,
    );
  });

  test('своя валюта с 4 знаками', () {
    expect(_minor(_parse('12,3456', 'ABC', digits: 4)), 123456);
    expect(
      _failure(_parse('1,23456', 'ABC', digits: 4)),
      AmountParseFailure.tooManyDecimals,
    );
  });

  test('рубль через currencyInfo ведёт себя как раньше', () {
    expect(_minor(_parse('7,5', 'RUB')), 750);
    expect(
      _failure(_parse('1,234', 'RUB')),
      AmountParseFailure.tooManyDecimals,
    );
  });
}
