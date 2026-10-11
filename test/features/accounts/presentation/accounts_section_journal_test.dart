import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';
import 'package:money_app/features/accounts/presentation/accounts_section.dart';

Account acc(String id, {bool archived = false}) => Account(
  id: id,
  name: 'Счёт $id',
  iconKey: 'card',
  openingBalance: Money.zero('RUB'),
  sortOrder: 0,
  currencyDigits: 2,
  archivedAt: archived ? DateTime.utc(2026, 9, 1) : null,
);

Future<void> pump(
  WidgetTester tester,
  List<Account> accounts, {
  VoidCallback? onOpenJournal,
  VoidCallback? onOpenOrder,
  VoidCallback? onTransfer,
  VoidCallback? onAddAccount,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: AccountsSection(
            accounts: Stream.value(accounts),
            balances: Stream.value({
              for (final a in accounts) a.id: Money.zero('RUB'),
            }),
            mainCurrency: 'RUB',
            onAddAccount: onAddAccount ?? () {},
            onOpenAccount: (_) {},
            onOpenJournal: onOpenJournal,
            onOpenOrder: onOpenOrder,
            onTransfer: onTransfer,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(AccountsSection.moreKey));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no accounts - no menu, only the main Add button', (
    tester,
  ) async {
    await pump(tester, [], onOpenJournal: () {});
    expect(find.byKey(AccountsSection.moreKey), findsNothing);
    expect(find.byKey(AccountsSection.addIconKey), findsNothing);
    expect(find.byKey(AccountsSection.addButtonKey), findsOneWidget);
    expect(find.byKey(AccountsSection.transferKey), findsNothing);
    expect(find.text(accountsSectionTitle), findsOneWidget);
    expect(find.text(accountsEmptyText), findsOneWidget);
  });

  testWidgets('with an account the menu opens the journal', (tester) async {
    final handle = tester.ensureSemantics();
    var opened = 0;
    await pump(tester, [acc('a')], onOpenJournal: () => opened++);
    await openMenu(tester);
    expect(find.text(balanceJournalButtonSpoken), findsOneWidget);
    expect(find.byKey(AccountsSection.orderKey), findsNothing);
    await tester.tap(find.byKey(AccountsSection.journalKey));
    await tester.pumpAndSettle();
    expect(opened, 1);
    handle.dispose();
  });

  testWidgets('only archived accounts - the menu is still there', (
    tester,
  ) async {
    await pump(tester, [acc('a', archived: true)], onOpenJournal: () {});
    expect(find.byKey(AccountsSection.moreKey), findsOneWidget);
  });

  testWidgets('without the callbacks there is no menu', (tester) async {
    await pump(tester, [acc('a')]);
    expect(find.byKey(AccountsSection.moreKey), findsNothing);
  });

  testWidgets('one account: main button is Add, no Transfer, no plus', (
    tester,
  ) async {
    var added = 0;
    await pump(
      tester,
      [acc('a')],
      onTransfer: () {},
      onAddAccount: () => added++,
    );
    expect(find.byKey(AccountsSection.transferKey), findsNothing);
    expect(find.byKey(AccountsSection.addIconKey), findsNothing);
    await tester.tap(find.byKey(AccountsSection.addButtonKey));
    expect(added, 1);
  });

  testWidgets('two accounts: main button is Transfer, plus adds, menu has both '
      'items', (tester) async {
    var transfers = 0;
    var added = 0;
    var order = 0;
    var journal = 0;
    await pump(
      tester,
      [acc('a'), acc('b')],
      onTransfer: () => transfers++,
      onAddAccount: () => added++,
      onOpenOrder: () => order++,
      onOpenJournal: () => journal++,
    );
    expect(find.byKey(AccountsSection.addButtonKey), findsNothing);
    await tester.tap(find.byKey(AccountsSection.transferKey));
    expect(transfers, 1);
    await tester.tap(find.byKey(AccountsSection.addIconKey));
    expect(added, 1);

    await openMenu(tester);
    expect(find.text(accountsOrderTitle), findsOneWidget);
    expect(find.text(balanceJournalButtonSpoken), findsOneWidget);
    await tester.tap(find.byKey(AccountsSection.orderKey));
    await tester.pumpAndSettle();
    expect(order, 1);
    await openMenu(tester);
    await tester.tap(find.byKey(AccountsSection.journalKey));
    await tester.pumpAndSettle();
    expect(journal, 1);
  });

  testWidgets('tap targets are at least 48 dp', (tester) async {
    await pump(
      tester,
      [acc('a'), acc('b')],
      onTransfer: () {},
      onOpenOrder: () {},
      onOpenJournal: () {},
    );
    for (final key in [
      AccountsSection.transferKey,
      AccountsSection.addIconKey,
      AccountsSection.moreKey,
    ]) {
      final size = tester.getSize(find.byKey(key));
      expect(size.width, greaterThanOrEqualTo(48), reason: '$key');
      expect(size.height, greaterThanOrEqualTo(48), reason: '$key');
    }
  });

  testWidgets('200% font: title, plus, menu and button do not overflow', (
    tester,
  ) async {
    await pump(
      tester,
      [acc('a'), acc('b')],
      onTransfer: () {},
      onOpenOrder: () {},
      onOpenJournal: () {},
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(AccountsSection.moreKey), findsOneWidget);
    expect(find.byKey(AccountsSection.addIconKey), findsOneWidget);
  });
}
