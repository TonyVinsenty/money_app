import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/currency_catalog.dart';

/// Снимок «код:знаков». Менять знаки выпущенной валюты нельзя никогда
/// (ADR 0010, п. 16.1): суммы в базе молча «поедут». Правка каталога видна здесь.
const String _snapshot =
    'RUB:2,USD:2,EUR:2,CNY:2,BTC:8,ETH:8,USDT:8,USDC:8,TON:8,BNB:8,SOL:8,'
    'XRP:8,TRX:8,DOGE:8,LTC:8';

const int _cryptoDigits = 8;
const int _cryptoCount = 11;

void main() {
  test('коды уникальны и проходят isValidCurrencyCode', () {
    final codes = currencyCatalog.map((c) => c.code).toList();
    expect(codes.toSet().length, codes.length);
    for (final code in codes) {
      expect(isValidCurrencyCode(code), isTrue, reason: code);
    }
  });

  test('крипта: 11 штук, у всех 8 знаков', () {
    final crypto = currencyCatalog.where((c) => c.kind == CurrencyKind.crypto);
    expect(crypto.length, _cryptoCount);
    for (final c in crypto) {
      expect(c.digits, _cryptoDigits, reason: c.code);
    }
  });

  test('снимок кодов и знаков', () {
    final actual = currencyCatalog
        .map((c) => '${c.code}:${c.digits}')
        .join(',');
    expect(actual, _snapshot);
  });

  test('catalogCurrency: есть и нет', () {
    expect(catalogCurrency('USD')?.symbol, r'$');
    expect(catalogCurrency('ABC'), isNull);
  });

  test('currencyInfoFor: каталог игнорирует переданные знаки', () {
    expect(currencyInfoFor('USD', digits: 4).digits, 2);
  });

  test('currencyInfoFor: своя валюта — символ и название равны коду', () {
    final info = currencyInfoFor('ABC', digits: 4);
    expect(info.kind, CurrencyKind.custom);
    expect(info.digits, 4);
    expect(info.symbol, 'ABC');
    expect(info.name, 'ABC');
    expect(info.forms, isNull);
  });

  test('currencyInfoFor: код не из каталога без знаков — assert', () {
    expect(() => currencyInfoFor('ABC'), throwsA(isA<AssertionError>()));
  });
}
