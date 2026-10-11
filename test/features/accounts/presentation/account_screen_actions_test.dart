import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/presentation/account_screen.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';

import '../../../support/fakes.dart';

Account _acc(String id, {String currency = 'RUB'}) => Account(
  id: id,
  name: 'Счёт $id',
  iconKey: 'card',
  openingBalance: Money.fromMinor(0, currency),
  sortOrder: 0,
  currencyDigits: 2,
);

Future<List<String>> _pump(
  WidgetTester tester, {
  required List<Account> accounts,
  String? defaultId,
  bool withMakeDefault = true,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final calls = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: AccountScreen(
        accounts: InMemoryAccountsRepository(accounts),
        accountId: 'a',
        defaultAccountId: defaultId,
        onEdit: (_) async => calls.add('edit'),
        onTransfer: (_) async => calls.add('transfer'),
        onShowTransactions: (_) => calls.add('operations'),
        onMakeDefault: withMakeDefault
            ? (_) async {
                calls.add('default');
                return true;
              }
            : null,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return calls;
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('каждое действие зовёт свой колбэк', (tester) async {
    final calls = await _pump(
      tester,
      accounts: [_acc('a'), _acc('b')],
      defaultId: 'b',
    );
    for (final key in [
      AccountScreen.editKey,
      AccountScreen.transferKey,
      AccountScreen.operationsKey,
      AccountScreen.makeDefaultKey,
    ]) {
      await tester.tap(find.byKey(key));
      await tester.pump();
    }
    expect(calls, ['edit', 'transfer', 'operations', 'default']);
    expect(find.byType(ListTile), findsNWidgets(5));
  });

  testWidgets('нет второго счёта и нет «Сделать основным» у основного', (
    tester,
  ) async {
    await _pump(tester, accounts: [_acc('a')], defaultId: 'a');
    expect(find.byKey(AccountScreen.transferKey), findsNothing);
    expect(find.byKey(AccountScreen.makeDefaultKey), findsNothing);
    expect(find.byKey(AccountScreen.editKey), findsOneWidget);
    expect(find.byKey(AccountScreen.adjustKey), findsOneWidget);
  });

  testWidgets('счёт в чужой валюте: нет «Операций» и «Сделать основным»', (
    tester,
  ) async {
    await _pump(
      tester,
      accounts: [
        _acc('a', currency: 'USD'),
        _acc('b'),
      ],
      defaultId: 'b',
    );
    expect(find.byKey(AccountScreen.operationsKey), findsNothing);
    expect(find.byKey(AccountScreen.makeDefaultKey), findsNothing);
  });

  testWidgets('строки не ниже 48 dp, озвучка по тексту', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, accounts: [_acc('a'), _acc('b')], defaultId: 'b');
    for (final key in [
      AccountScreen.editKey,
      AccountScreen.adjustKey,
      AccountScreen.transferKey,
      AccountScreen.operationsKey,
      AccountScreen.makeDefaultKey,
    ]) {
      expect(tester.getSize(find.byKey(key)).height, greaterThanOrEqualTo(48));
    }
    for (final label in [
      accountEditButton,
      accountAdjustButton,
      transferButtonLabel,
      accountOperationsButton,
      accountMakeDefaultButton,
    ]) {
      expect(find.bySemanticsLabel(label), findsOneWidget, reason: label);
    }
    handle.dispose();
  });

  testWidgets('360 dp и шрифт 200 %: без переполнения', (tester) async {
    await _pump(
      tester,
      accounts: [_acc('a'), _acc('b')],
      defaultId: 'b',
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });
}
