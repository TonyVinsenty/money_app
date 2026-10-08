import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/features/export/domain/transactions_export.dart';

void main() {
  test('BTC: ровно 8 знаков', () {
    expect(formatCsvAmount(Money.fromMinor(150000, 'BTC')), '0,00150000');
    expect(formatCsvAmount(Money.fromMinor(100000000, 'BTC')), '1,00000000');
  });
  test('JPY: без запятой', () {
    expect(formatCsvAmount(Money.fromMinor(1500, 'JPY')), '1500');
  });
  test('KWD: 3 знака', () {
    expect(formatCsvAmount(Money.fromMinor(12345, 'KWD')), '12,345');
  });
  test('своя валюта с 4 знаками через currency', () {
    expect(
      formatCsvAmount(
        Money.fromMinor(123456, 'ABC'),
        currency: currencyInfoFor('ABC', digits: 4),
      ),
      '12,3456',
    );
  });
  test('рубль и отрицательная сумма как раньше', () {
    expect(formatCsvAmount(Money.fromMinor(35000, 'RUB')), '350,00');
    expect(
      () => formatCsvAmount(Money.fromMinor(-1, 'JPY')),
      throwsArgumentError,
    );
  });
}
