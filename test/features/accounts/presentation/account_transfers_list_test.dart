import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/card_header.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/transfer.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';
import 'package:money_app/features/accounts/presentation/account_transfers_list.dart';

Account _acc(String id, String name, {int digits = 2}) => Account(
  id: id,
  name: name,
  iconKey: 'card',
  openingBalance: Money.zero('RUB'),
  sortOrder: 0,
  currencyDigits: digits,
);

Transfer _transfer(String id, int minor) => Transfer(
  id: id,
  fromAccountId: 'a1',
  toAccountId: 'a2',
  amount: Money.fromMinor(minor, 'RUB'),
  occurredOn: DateOnly(2026, 10, 9),
  occurredAt: DateTime.utc(2026, 10, 9, 9),
);

Future<void> _pump(WidgetTester tester, int minor, double scale) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: AccountTransfersList(
            transfers: Stream.value([_transfer('t1', minor)]),
            accounts: [_acc('a1', 'Карта'), _acc('a2', 'Наличные')],
            accountId: 'a1',
            currency: currencyInfoFor('RUB', digits: 2),
            today: DateOnly(2026, 10, 10),
            onOpen: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('transfer amount is not smaller than title, tabular digits', (
    tester,
  ) async {
    await _pump(tester, 500000, 1);
    final row = find.byKey(AccountTransfersList.rowKey('t1'));
    final amount = tester.widget<Text>(
      find.descendant(of: row, matching: find.textContaining('5')),
    );
    final bodyLarge = Theme.of(tester.element(row)).textTheme.bodyLarge!;
    expect(amount.style!.fontSize, greaterThanOrEqualTo(bodyLarge.fontSize!));
    expect(
      amount.style!.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
  });

  testWidgets('section title is a CardHeader with weight 600', (tester) async {
    await _pump(tester, 500000, 1);
    final header = find.byType(CardHeader);
    expect(header, findsOneWidget);
    final title = tester.widget<Text>(
      find.descendant(of: header, matching: find.text(transfersSectionTitle)),
    );
    expect(title.style?.fontWeight, FontWeight.w600);
  });

  testWidgets('long amount at 200% on 360 dp: no overflow', (tester) async {
    await _pump(tester, 99999999999999, 2);
    expect(tester.takeException(), isNull);
  });
}
