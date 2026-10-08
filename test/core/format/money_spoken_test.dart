import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';

Money rub(int minor) => Money.fromMinor(minor, 'RUB');

void main() {
  group('spokenMoney: склонение рублей', () {
    const cases = <int, String>{
      1: 'рубль',
      2: 'рубля',
      5: 'рублей',
      11: 'рублей',
      12: 'рублей',
      14: 'рублей',
      21: 'рубль',
      22: 'рубля',
      25: 'рублей',
      100: 'рублей',
      101: 'рубль',
      111: 'рублей',
    };
    cases.forEach((n, word) {
      test('$n -> $word', () {
        expect(spokenMoney(rub(n * 100)), '$n $word');
      });
    });
  });

  group('spokenMoney: склонение копеек', () {
    const cases = <int, String>{
      1: 'копейка',
      2: 'копейки',
      5: 'копеек',
      11: 'копеек',
      12: 'копеек',
      14: 'копеек',
      21: 'копейка',
      22: 'копейки',
      25: 'копеек',
    };
    cases.forEach((n, word) {
      test('$n -> $word', () {
        expect(spokenMoney(rub(300 + n)), '3 рубля $n $word');
      });
    });

    test('наибольшее число копеек 99 читается как «копеек»', () {
      expect(spokenMoney(rub(99)), '0 рублей 99 копеек');
    });
  });

  group('spokenMoney: общие случаи', () {
    test('рубли и копейки без разделителя разрядов', () {
      expect(spokenMoney(rub(123450)), '1234 рубля 50 копеек');
    });

    test('21 рубль 1 копейка', () {
      expect(spokenMoney(rub(2101)), '21 рубль 1 копейка');
    });

    test('без копеек не читается «ноль копеек»', () {
      expect(spokenMoney(rub(500)), '5 рублей');
      expect(spokenMoney(rub(100)), '1 рубль');
    });

    test('ноль', () {
      expect(spokenMoney(rub(0)), '0 рублей');
    });

    test('только копейки: рубли называются как ноль', () {
      expect(spokenMoney(rub(50)), '0 рублей 50 копеек');
      expect(spokenMoney(rub(1)), '0 рублей 1 копейка');
    });

    test('отрицательная сумма получает «минус »', () {
      expect(spokenMoney(rub(-123450)), 'минус 1234 рубля 50 копеек');
      expect(spokenMoney(rub(-500)), 'минус 5 рублей');
      expect(spokenMoney(rub(-1)), 'минус 0 рублей 1 копейка');
    });

    test('большая сумма: 1 000 000 000 000 рублей', () {
      expect(spokenMoney(rub(100000000000000)), '1000000000000 рублей');
    });

    test('код не из каталога без знаков — 2 знака, число и код', () {
      expect(spokenMoney(Money.fromMinor(150, 'GBP')), '1,5, GBP');
    });
  });

  group('spokenMoney: другие валюты (ADR 0010, п. 16.6)', () {
    Money m(int minor, String code) => Money.fromMinor(minor, code);

    test('доллар: 1 / 2 / 5 / 11', () {
      expect(spokenMoney(m(100, 'USD')), '1 доллар');
      expect(spokenMoney(m(200, 'USD')), '2 доллара');
      expect(spokenMoney(m(500, 'USD')), '5 долларов');
      expect(spokenMoney(m(1100, 'USD')), '11 долларов');
      expect(spokenMoney(m(0, 'USD')), '0 долларов');
    });

    test('дробная сумма — вторая форма, нули срезаны', () {
      expect(spokenMoney(m(1250, 'USD')), '12,5 доллара');
      expect(spokenMoney(m(150000, 'BTC')), '0,0015 биткоина');
    });

    test('минус и евро', () {
      expect(spokenMoney(m(-300, 'EUR')), 'минус 3 евро');
    });

    test('крупная сумма без разделителя разрядов', () {
      expect(spokenMoney(m(123456700, 'USD')), '1234567 долларов');
    });

    test('каталожная валюта без слов — число, название', () {
      expect(spokenMoney(m(150000000, 'USDT')), '1,5, Tether');
      expect(spokenMoney(m(-100000000, 'TON')), 'минус 1, Toncoin');
    });

    test('своя валюта — число, код', () {
      final abc0 = currencyInfoFor('ABC', digits: 0);
      final abc4 = currencyInfoFor('ABC', digits: 4);
      expect(spokenMoney(m(1500, 'ABC'), currency: abc0), '1500, ABC');
      expect(spokenMoney(m(125000, 'ABC'), currency: abc4), '12,5, ABC');
    });
  });
}
