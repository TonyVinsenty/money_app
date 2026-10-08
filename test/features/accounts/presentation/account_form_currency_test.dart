import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/money/parse_amount.dart';
import 'package:money_app/core/ui/amount_failure_text.dart';
import 'package:money_app/core/ui/currency_picker.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/presentation/account_form_screen.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';

import '../../../support/fake_id_generator.dart';
import '../../../support/fakes.dart';

Future<void> pumpForm(
  WidgetTester tester,
  InMemoryAccountsRepository repo, {
  Account? editing,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: AccountFormScreen(
        accounts: repo,
        idGenerator: FakeIdGenerator(),
        currency: 'RUB',
        editing: editing,
      ),
    ),
  );
}

Future<void> pick(WidgetTester tester, String query, String name) async {
  await tester.tap(find.byKey(AccountFormScreen.currencyRowKey));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextField, currencyPickerSearchHint),
    query,
  );
  await tester.pump();
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

TextField balanceField(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(AccountFormScreen.balanceFieldKey));

void main() {
  testWidgets('new account: ruble by default', (tester) async {
    await pumpForm(tester, InMemoryAccountsRepository());
    expect(find.text(accountFormCurrencyTitle), findsOneWidget);
    expect(find.text('Российский рубль, ₽'), findsOneWidget);
  });

  testWidgets('BTC: account created in BTC with 0,0015; 9th digit rejected', (
    tester,
  ) async {
    final repo = InMemoryAccountsRepository();
    await pumpForm(tester, repo);
    await pick(tester, 'btc', 'Биткоин');
    expect(find.text('Биткоин, BTC'), findsOneWidget);

    await tester.enterText(
      find.byKey(AccountFormScreen.nameFieldKey),
      'Кошелёк',
    );
    final field = find.byKey(AccountFormScreen.balanceFieldKey);
    await tester.enterText(field, '0,12345678');
    await tester.enterText(field, '0,123456789');
    expect(balanceField(tester).controller!.text, '0,12345678');
    await tester.enterText(field, '0,0015');
    await tester.tap(find.byKey(AccountFormScreen.saveButtonKey));
    await tester.pumpAndSettle();

    final saved = repo.all.single;
    expect(saved.currency, 'BTC');
    expect(saved.currencyDigits, 8);
    expect(saved.openingBalance, Money.fromMinor(150000, 'BTC'));
  });

  testWidgets('currency with fewer digits: field error, amount kept', (
    tester,
  ) async {
    final repo = InMemoryAccountsRepository();
    await pumpForm(tester, repo);
    await tester.enterText(find.byKey(AccountFormScreen.nameFieldKey), 'Йена');
    await tester.enterText(
      find.byKey(AccountFormScreen.balanceFieldKey),
      '1,50',
    );
    await pick(tester, 'jpy', 'Японская иена');

    final jpy = catalogCurrency('JPY')!;
    final failure = (parseAmount(
      '1,50',
      currency: 'JPY',
      currencyInfo: jpy,
    ) as AmountParseFailed).failure;
    expect(
      find.text(amountFailureMessage(failure, currency: jpy)),
      findsOneWidget,
    );
    expect(balanceField(tester).controller!.text, '1,50');

    await tester.tap(find.byKey(AccountFormScreen.saveButtonKey));
    await tester.pumpAndSettle();
    expect(repo.all, isEmpty);
  });

  testWidgets('keyboard: no decimal separator for zero-digit currencies', (
    tester,
  ) async {
    await pumpForm(tester, InMemoryAccountsRepository());
    expect(balanceField(tester).keyboardType.decimal, isTrue);
    await pick(tester, 'jpy', 'Японская иена');
    expect(balanceField(tester).keyboardType.decimal, isFalse);
    await pick(tester, 'usd', 'Доллар США');
    expect(balanceField(tester).keyboardType.decimal, isTrue);
  });

  testWidgets('edit: currency is text, cannot be chosen', (tester) async {
    final account = Account(
      id: 'a',
      name: 'Крипта',
      iconKey: 'card',
      openingBalance: Money.zero('BTC'),
      sortOrder: 0,
      currencyDigits: 8,
    );
    await pumpForm(
      tester,
      InMemoryAccountsRepository([account]),
      editing: account,
    );
    expect(find.text('Биткоин, BTC — не меняется'), findsOneWidget);
    await tester.tap(find.byKey(AccountFormScreen.currencyRowKey));
    await tester.pumpAndSettle();
    expect(find.text(currencyPickerSearchHint), findsNothing);
  });
}
