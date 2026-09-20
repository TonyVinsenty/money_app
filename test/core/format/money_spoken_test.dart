import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/format/money_spoken.dart';
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

    test('чужая валюта — ArgumentError', () {
      expect(
        () => spokenMoney(Money.fromMinor(100, 'USD')),
        throwsArgumentError,
      );
    });
  });
}
