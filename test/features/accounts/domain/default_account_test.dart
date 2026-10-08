import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/default_account.dart';

Account _acc(String id, {String currency = 'RUB', bool archived = false}) =>
    Account(
      id: id,
      name: 'Счёт $id',
      iconKey: 'card',
      openingBalance: Money.zero(currency),
      sortOrder: 0,
      currencyDigits: 2,
      archivedAt: archived ? DateTime.utc(2026, 9, 1) : null,
    );

void main() {
  test('находит счёт по id в основной валюте', () {
    final a = _acc('a');
    expect(resolveDefaultAccount([_acc('b'), a], 'a', 'RUB'), a);
  });

  test('нет записи, нет счёта, архив, другая валюта - основного нет', () {
    expect(resolveDefaultAccount([_acc('a')], null, 'RUB'), isNull);
    expect(resolveDefaultAccount([_acc('a')], 'zzz', 'RUB'), isNull);
    expect(
      resolveDefaultAccount([_acc('a', archived: true)], 'a', 'RUB'),
      isNull,
    );
    expect(
      resolveDefaultAccount([_acc('a', currency: 'USD')], 'a', 'RUB'),
      isNull,
    );
    expect(
      resolveDefaultAccount([_acc('a', currency: 'USD')], 'a', 'USD'),
      isNotNull,
    );
  });
}
