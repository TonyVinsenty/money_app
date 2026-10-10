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
            onAddAccount: () {},
            onOpenAccount: (_) {},
            onOpenJournal: onOpenJournal,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('no accounts - no journal button', (tester) async {
    await pump(tester, [], onOpenJournal: () {});
    expect(find.byKey(AccountsSection.journalKey), findsNothing);
    expect(find.text(accountsSectionTitle), findsOneWidget);
  });

  testWidgets('with an account the button shows and calls the callback', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    var opened = 0;
    await pump(tester, [acc('a')], onOpenJournal: () => opened++);
    expect(find.text(balanceJournalButton), findsOneWidget);
    expect(find.bySemanticsLabel(balanceJournalButtonSpoken), findsOneWidget);
    await tester.tap(find.byKey(AccountsSection.journalKey));
    expect(opened, 1);
    handle.dispose();
  });

  testWidgets('only archived accounts - the button is still there', (
    tester,
  ) async {
    await pump(tester, [acc('a', archived: true)], onOpenJournal: () {});
    expect(find.byKey(AccountsSection.journalKey), findsOneWidget);
  });

  testWidgets('without the callback there is no button', (tester) async {
    await pump(tester, [acc('a')]);
    expect(find.byKey(AccountsSection.journalKey), findsNothing);
  });

  testWidgets('200% font: title and button do not overflow', (tester) async {
    await pump(tester, [acc('a')], onOpenJournal: () {}, textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.byKey(AccountsSection.journalKey), findsOneWidget);
  });
}
