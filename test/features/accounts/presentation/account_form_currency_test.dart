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
import 'package:money_app/features/accounts/presentation/custom_currency_dialog.dart';

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

/// Нажимает строку валюты. Список счетов читается из потока (нужен настоящий
/// тик), поэтому после нажатия даём ему отработать.
Future<void> openPicker(WidgetTester tester) async {
  await tester.tap(find.byKey(AccountFormScreen.currencyRowKey));
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pump();
  await tester.pumpAndSettle();
}

Future<void> pick(WidgetTester tester, String query, String name) async {
  await openPicker(tester);
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
    await openPicker(tester);
    expect(find.text(currencyPickerSearchHint), findsNothing);
  });

  Future<void> openCustom(WidgetTester tester) async {
    await openPicker(tester);
    await tester.enterText(
      find.widgetWithText(TextField, currencyPickerSearchHint),
      'qqq',
    );
    await tester.pump();
    await tester.tap(find.text(currencyPickerCustom));
    await tester.pumpAndSettle();
  }

  Future<void> fillCustom(WidgetTester tester, String code, [String? digits]) {
    return () async {
      await tester.enterText(
        find.byKey(CustomCurrencyDialog.codeFieldKey),
        code,
      );
      if (digits != null) {
        await tester.enterText(
          find.byKey(CustomCurrencyDialog.digitsFieldKey),
          digits,
        );
      }
      await tester.pump();
    }();
  }

  Future<void> done(WidgetTester tester) async {
    await tester.tap(find.byKey(CustomCurrencyDialog.doneKey));
    await tester.pumpAndSettle();
  }

  testWidgets('custom: abc becomes ABC, 4 digits, account with 12,3456', (
    tester,
  ) async {
    final repo = InMemoryAccountsRepository();
    await pumpForm(tester, repo);
    await openCustom(tester);
    expect(find.text(customCurrencyTitle), findsOneWidget);
    expect(find.text(customCurrencyExplain), findsOneWidget);
    await fillCustom(tester, 'abc', '4');
    expect(
      tester
          .widget<TextField>(find.byKey(CustomCurrencyDialog.codeFieldKey))
          .controller!
          .text,
      'ABC',
    );
    await done(tester);
    expect(find.text('ABC, ABC'), findsOneWidget);

    await tester.enterText(find.byKey(AccountFormScreen.nameFieldKey), 'Свой');
    await tester.enterText(
      find.byKey(AccountFormScreen.balanceFieldKey),
      '12,3456',
    );
    await tester.tap(find.byKey(AccountFormScreen.saveButtonKey));
    await tester.pumpAndSettle();
    final saved = repo.all.single;
    expect(saved.openingBalance, Money.fromMinor(123456, 'ABC'));
    expect(saved.currencyDigits, 4);
  });

  for (final bad in ['US', '1AB', 'AB-C']) {
    testWidgets('custom: code $bad is an error', (tester) async {
      await pumpForm(tester, InMemoryAccountsRepository());
      await openCustom(tester);
      await fillCustom(tester, bad);
      await done(tester);
      expect(find.text(customCurrencyCodeError), findsOneWidget);
      expect(find.text(customCurrencyTitle), findsOneWidget);
    });
  }

  testWidgets('custom: digits out of range is an error', (tester) async {
    await pumpForm(tester, InMemoryAccountsRepository());
    await openCustom(tester);
    await fillCustom(tester, 'abc', '9');
    await done(tester);
    expect(find.text(customCurrencyDigitsError), findsOneWidget);
    await fillCustom(tester, 'abc', '');
    await done(tester);
    expect(find.text(customCurrencyDigitsError), findsOneWidget);
  });

  testWidgets('custom: usdt gives the catalog entry silently', (tester) async {
    await pumpForm(tester, InMemoryAccountsRepository());
    await openCustom(tester);
    await fillCustom(tester, 'usdt');
    expect(find.textContaining('Как у счёта'), findsNothing);
    await done(tester);
    expect(find.text('Tether, USDT'), findsOneWidget);
    await tester.enterText(find.byKey(AccountFormScreen.nameFieldKey), 'T');
    await tester.enterText(
      find.byKey(AccountFormScreen.balanceFieldKey),
      '0,12345678',
    );
    expect(balanceField(tester).controller!.text, '0,12345678');
  });

  testWidgets('custom: code of an (archived) account locks digits; yours '
      'group and search find it', (tester) async {
    final existing = Account(
      id: 'a',
      name: 'Кошелёк',
      iconKey: 'card',
      openingBalance: Money.zero('ABC'),
      sortOrder: 0,
      currencyDigits: 4,
      archivedAt: DateTime.utc(2026, 1, 1),
    );
    final repo = InMemoryAccountsRepository([existing]);
    await pumpForm(tester, repo);

    // «Ваши валюты» и поиск.
    await openPicker(tester);
    expect(find.text(currencyPickerYours), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextField, currencyPickerSearchHint),
      'abc',
    );
    await tester.pump();
    expect(find.text('ABC'), findsNWidgets(2)); // название и подпись
    await tester.tapAt(const Offset(10, 10)); // закрыть лист по фону
    await tester.pumpAndSettle();

    await openCustom(tester);
    await fillCustom(tester, 'abc');
    final digits = tester.widget<TextField>(
      find.byKey(CustomCurrencyDialog.digitsFieldKey),
    );
    expect(digits.enabled, isFalse);
    expect(digits.controller!.text, '4');
    expect(find.text(customCurrencyLikeAccount('Кошелёк')), findsOneWidget);
    await done(tester);
    expect(find.text('ABC, ABC'), findsOneWidget);
    await tester.enterText(find.byKey(AccountFormScreen.nameFieldKey), 'Ещё');
    await tester.enterText(
      find.byKey(AccountFormScreen.balanceFieldKey),
      '1,2345',
    );
    await tester.tap(find.byKey(AccountFormScreen.saveButtonKey));
    await tester.pumpAndSettle();
    expect(repo.all.last.currencyDigits, 4);
  });

  testWidgets('custom dialog: catalog code shows a hint, unknown code not', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: CustomCurrencyDialog(accounts: [])),
      ),
    );
    const hint = 'Есть в списке: Доллар США. Знаков после запятой: 2';
    await tester.enterText(
      find.byKey(CustomCurrencyDialog.codeFieldKey),
      'USD',
    );
    await tester.pump();
    expect(find.text(hint), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(CustomCurrencyDialog.digitsFieldKey))
          .enabled,
      isFalse,
    );

    await tester.enterText(
      find.byKey(CustomCurrencyDialog.codeFieldKey),
      'ABC',
    );
    await tester.pump();
    expect(find.textContaining('Есть в списке'), findsNothing);
    expect(
      tester
          .widget<TextField>(find.byKey(CustomCurrencyDialog.digitsFieldKey))
          .enabled,
      isTrue,
    );
  });

  testWidgets('custom dialog scrolls at font 200 %', (tester) async {
    tester.view.physicalSize = const Size(360, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(body: CustomCurrencyDialog(accounts: [])),
      ),
    );
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
