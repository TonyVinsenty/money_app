import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/accounts/domain/account_rules.dart';

void expectMismatch(String currency, int digits, List<(String, int)> existing) {
  expect(
    () => checkCurrencyDigits(
      currency: currency,
      digits: digits,
      existing: existing,
    ),
    throwsA(
      isA<AccountRuleException>().having(
        (e) => e.rule,
        'rule',
        AccountRule.currencyDigitsMismatch,
      ),
    ),
  );
}

void main() {
  group('checkCurrencyDigits', () {
    test('catalog currency with foreign digits is an error', () {
      expectMismatch('USD', 4, const []);
      expectMismatch('BTC', 2, const []);
      expectMismatch('JPY', 2, const []);
    });

    test('catalog currency with catalog digits passes', () {
      checkCurrencyDigits(currency: 'USD', digits: 2, existing: const []);
      checkCurrencyDigits(currency: 'BTC', digits: 8, existing: const []);
      checkCurrencyDigits(currency: 'JPY', digits: 0, existing: const []);
    });

    test('custom code with other digits than an existing account', () {
      expectMismatch('ABC', 3, const [('ABC', 4)]);
    });

    test('custom code with the same digits passes', () {
      checkCurrencyDigits(
        currency: 'ABC',
        digits: 4,
        existing: const [('ABC', 4), ('XYZ', 0)],
      );
    });

    test('new custom code takes any digits', () {
      checkCurrencyDigits(
        currency: 'ABC',
        digits: 7,
        existing: const [('XYZ', 0)],
      );
    });
  });
}
