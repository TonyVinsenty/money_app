import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/currency_catalog.dart';

/// Снимок «код:знаков». Менять знаки выпущенной валюты нельзя никогда
/// (ADR 0010, п. 16.1): суммы в базе молча «поедут». Правка каталога видна здесь.
const String _snapshot =
    'RUB:2,USD:2,EUR:2,CNY:2,BTC:8,ETH:8,USDT:8,USDC:8,TON:8,BNB:8,SOL:8,XR'
    'P:8,TRX:8,DOGE:8,LTC:8,AED:2,AFN:0,ALL:0,AMD:2,ANG:2,AOA:2,ARS:2,AUD:2'
    ',AWG:2,AZN:2,BAM:2,BBD:2,BDT:2,BGN:2,BHD:3,BIF:0,BMD:2,BND:2,BOB:2,BRL'
    ':2,BSD:2,BTN:2,BWP:2,BYN:2,BZD:2,CAD:2,CDF:2,CHF:2,CLP:0,COP:0,CRC:2,C'
    'UP:2,CVE:2,CZK:2,DJF:0,DKK:2,DOP:2,DZD:2,EGP:2,ERN:2,ETB:2,FJD:2,FKP:2'
    ',GBP:2,GEL:2,GHS:2,GIP:2,GMD:2,GNF:0,GTQ:2,GYD:2,HKD:2,HNL:2,HTG:2,HUF'
    ':0,IDR:0,ILS:2,INR:2,IQD:0,IRR:0,ISK:0,JMD:2,JOD:3,JPY:0,KES:2,KGS:2,K'
    'HR:2,KMF:0,KPW:0,KRW:0,KWD:3,KYD:2,KZT:2,LAK:0,LBP:0,LKR:2,LRD:2,LSL:2'
    ',LYD:3,MAD:2,MDL:2,MGA:0,MKD:2,MMK:0,MNT:2,MOP:2,MRU:2,MUR:2,MVR:2,MWK'
    ':2,MXN:2,MYR:2,MZN:2,NAD:2,NGN:2,NIO:2,NOK:2,NPR:2,NZD:2,OMR:3,PAB:2,P'
    'EN:2,PGK:2,PHP:2,PKR:0,PLN:2,PYG:0,QAR:2,RON:2,RSD:0,RWF:0,SAR:2,SBD:2'
    ',SCR:2,SDG:2,SEK:2,SGD:2,SHP:2,SLE:2,SOS:0,SRD:2,SSP:2,STN:2,SVC:2,SYP'
    ':0,SZL:2,THB:2,TJS:2,TMT:2,TND:3,TOP:2,TRY:2,TTD:2,TWD:2,TZS:2,UAH:2,U'
    'GX:0,UYU:2,UZS:2,VES:2,VND:0,VUV:0,WST:2,XAF:0,XCD:2,XOF:0,XPF:0,YER:0'
    ',ZAR:2,ZMW:2,ZWG:2';
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

  group('обычные валюты', () {
    final fiat = currencyCatalog
        .where((c) => c.kind == CurrencyKind.fiat)
        .toList();

    test('количество 150-170, код из трёх букв, непустое название', () {
      expect(fiat.length, inInclusiveRange(150, 170));
      for (final c in fiat) {
        expect(isIsoCurrencyCode(c.code), isTrue, reason: c.code);
        expect(c.name.trim(), isNotEmpty, reason: c.code);
      }
    });

    test('коды не совпадают с криптой', () {
      final crypto = currencyCatalog
          .where((c) => c.kind == CurrencyKind.crypto)
          .map((c) => c.code)
          .toSet();
      expect(fiat.where((c) => crypto.contains(c.code)), isEmpty);
    });

    test('знаки совпадают с intl (исключений нет)', () {
      for (final c in fiat) {
        final expected = NumberFormat.currency(
          locale: 'en',
          name: c.code,
        ).decimalDigits;
        expect(c.digits, expected, reason: c.code);
      }
    });

    test('нет фондовых и служебных кодов', () {
      const excluded = <String>{
        'BOV', 'CHE', 'CHW', 'CLF', 'COU', 'MXV', 'USN', 'UYI', 'UYW', //
        'XAU', 'XAG', 'XPD', 'XPT', 'XDR', 'XSU', 'XUA', 'XBA', 'XBB', //
        'XBC', 'XBD', 'XTS', 'XXX',
      };
      expect(fiat.where((c) => excluded.contains(c.code)), isEmpty);
    });

    test('символы только из списка, у остальных символ равен коду', () {
      const symbols = <String, String>{
        'RUB': '₽',
        'USD': r'$',
        'EUR': '€',
        'GBP': '£',
        'CNY': '¥',
        'KZT': '₸',
        'UAH': '₴',
        'TRY': '₺',
        'GEL': '₾',
        'AMD': '֏',
        'AZN': '₼',
        'INR': '₹',
        'KRW': '₩',
        'ILS': '₪',
        'THB': '฿',
        'VND': '₫',
        'PHP': '₱',
        'NGN': '₦',
        'MNT': '₮',
      };
      for (final c in fiat) {
        expect(c.symbol, symbols[c.code] ?? c.code, reason: c.code);
      }
    });

    test('слова озвучки у фунта, иены, тенге и других', () {
      for (final code in ['GBP', 'JPY', 'KZT', 'GEL', 'AMD']) {
        expect(catalogCurrency(code)?.forms, isNotNull, reason: code);
      }
      expect(catalogCurrency('TRY')?.forms, isNull);
    });
  });
}
