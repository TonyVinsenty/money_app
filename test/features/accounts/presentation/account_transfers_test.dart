import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/balance_tab.dart';
import 'package:money_app/core/format/day_label.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/transfer.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';
import 'package:money_app/features/accounts/presentation/account_transfers_list.dart';
import 'package:money_app/features/accounts/presentation/transfer_form_screen.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

import '../../../support/fakes.dart';
import '../../../support/fixed_clock.dart';

Account acc(String id, String name, {bool archived = false}) => Account(
  id: id,
  name: name,
  iconKey: 'card',
  openingBalance: Money.zero('RUB'),
  sortOrder: 0,
  currencyDigits: 2,
  archivedAt: archived ? DateTime.utc(2026, 9, 1) : null,
);

Money rub(int minor) => Money.fromMinor(minor, 'RUB');

Transfer transfer(
  String id,
  String from,
  String to,
  int minor,
  int day, {
  String? note,
}) => Transfer(
  id: id,
  fromAccountId: from,
  toAccountId: to,
  amount: rub(minor),
  occurredOn: DateOnly(2026, 9, day),
  occurredAt: DateTime.utc(2026, 9, day, 9),
  note: note,
);

final clock = FixedClock(DateTime.utc(2026, 9, 20, 12));

Future<void> openAccount(
  WidgetTester tester,
  List<Account> accounts,
  InMemoryTransfersRepository transfers, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = AppSettingsController();
  addTearDown(settings.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      onGenerateRoute: onGenerateAppRoute,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: AppScope(
        services: fakeAppServices(
          settings: settings,
          accounts: InMemoryAccountsRepository(accounts),
          transfers: transfers,
          clock: clock,
        ),
        child: const Scaffold(body: BalanceTab()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.tap(find.text('Карта'));
  await tester.pumpAndSettle();
}

final cardAndCash = [acc('a1', 'Карта'), acc('a2', 'Наличные')];

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('shows both directions with text and spoken label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final transfers = InMemoryTransfersRepository([
      transfer('t1', 'a1', 'a2', 500000, 7, note: 'Аренда'),
      transfer('t2', 'a2', 'a1', 30000, 8),
    ]);
    await openAccount(tester, cardAndCash, transfers);

    expect(find.text(transfersSectionTitle), findsOneWidget);
    expect(find.text('→ Наличные'), findsOneWidget);
    expect(find.text(formatMoney(-rub(500000))), findsOneWidget);
    expect(find.text('← Наличные'), findsOneWidget);
    expect(find.text('+${formatMoney(rub(30000))}'), findsOneWidget);
    expect(find.text('Аренда'), findsOneWidget);
    expect(find.text('7 сентября'), findsNothing);
    // С комментарием озвучка заканчивается комментарием.
    expect(
      find.bySemanticsLabel(
        'Перевод на счёт Наличные, минус 5000 рублей, 7 сентября, '
        'комментарий: Аренда',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Перевод со счёта Наличные, плюс 300 рублей, 8 сентября',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('no transfers - no section', (tester) async {
    await openAccount(tester, cardAndCash, InMemoryTransfersRepository());
    expect(find.byKey(AccountTransfersList.sectionKey), findsNothing);
    expect(find.text(transfersSectionTitle), findsNothing);
  });

  testWidgets('archived partner is marked', (tester) async {
    final transfers = InMemoryTransfersRepository([
      transfer('t1', 'a1', 'a2', 100, 7),
    ]);
    await openAccount(tester, [
      acc('a1', 'Карта'),
      acc('a2', 'Старая', archived: true),
    ], transfers);
    expect(find.text('→ Старая (в архиве)'), findsOneWidget);
    expect(find.text(formatMoney(-rub(100))), findsOneWidget);
  });

  testWidgets('unknown partner is called "другой счёт", also spoken', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final transfers = InMemoryTransfersRepository([
      transfer('t1', 'a1', 'gone', 100, 7),
    ]);
    await openAccount(tester, cardAndCash, transfers);
    expect(find.text('→ $transferUnknownPartner'), findsOneWidget);
    expect(
      find.bySemanticsLabel(
        RegExp(
          'Перевод на счёт $transferUnknownPartner, минус 1 рубль, 7 сентября',
        ),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('section title and day headings are headers', (tester) async {
    final handle = tester.ensureSemantics();
    final transfers = InMemoryTransfersRepository([
      transfer('t1', 'a1', 'a2', 100, 7),
    ]);
    await openAccount(tester, cardAndCash, transfers);
    expect(
      tester
          .getSemantics(find.text(transfersSectionTitle))
          .flagsCollection
          .isHeader,
      isTrue,
    );
    expect(
      tester
          .getSemantics(
            find.text(
              historyDayLabel(
                DateOnly(2026, 9, 7),
                today: DateOnly(2026, 9, 20),
              ),
            ),
          )
          .flagsCollection
          .isHeader,
      isTrue,
    );
    handle.dispose();
  });

  testWidgets('long partner name and amount live in one row without overflow', (
    tester,
  ) async {
    final transfers = InMemoryTransfersRepository([
      transfer('t1', 'a1', 'a2', 123456789, 7),
    ]);
    await openAccount(
      tester,
      [acc('a1', 'Карта'), acc('a2', 'Очень длинное название для проверки')],
      transfers,
      textScale: 2,
    );
    expect(find.byKey(AccountTransfersList.rowKey('t1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap opens edit form; delete closes it, undo restores', (
    tester,
  ) async {
    final transfers = InMemoryTransfersRepository([
      transfer('t1', 'a1', 'a2', 500000, 7),
    ]);
    await openAccount(tester, cardAndCash, transfers);

    await tester.tap(find.byKey(AccountTransfersList.rowKey('t1')));
    await tester.pumpAndSettle();
    expect(find.text(transferFormEditTitle), findsOneWidget);
    expect(find.byTooltip(transferDeleteTooltip), findsOneWidget);

    await tester.tap(find.byTooltip(transferDeleteTooltip));
    await tester.pumpAndSettle();
    expect(transfers.all, isEmpty);
    expect(find.text(transferFormEditTitle), findsNothing);
    expect(find.text(transferDeletedText), findsOneWidget);
    expect(find.byKey(AccountTransfersList.sectionKey), findsNothing);

    await tester.tap(find.text(transferUndoLabel));
    await tester.pumpAndSettle();
    expect(transfers.all, hasLength(1));
    expect(find.byKey(AccountTransfersList.rowKey('t1')), findsOneWidget);
  });

  testWidgets('delete failure keeps the form open with a message', (
    tester,
  ) async {
    final transfers = InMemoryTransfersRepository([
      transfer('t1', 'a1', 'a2', 500000, 7),
    ])..failDeleteWith = Exception('db');
    await openAccount(tester, cardAndCash, transfers);
    await tester.tap(find.byKey(AccountTransfersList.rowKey('t1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip(transferDeleteTooltip));
    await tester.pumpAndSettle();
    expect(find.text(transferDeleteFailedText), findsOneWidget);
    expect(find.byKey(TransferFormScreen.saveKey), findsOneWidget);
    expect(transfers.all, hasLength(1));
  });

  testWidgets('undo failure shows a message', (tester) async {
    final transfers = InMemoryTransfersRepository([
      transfer('t1', 'a1', 'a2', 500000, 7),
    ]);
    await openAccount(tester, cardAndCash, transfers);
    await tester.tap(find.byKey(AccountTransfersList.rowKey('t1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(transferDeleteTooltip));
    await tester.pumpAndSettle();

    transfers.failDeleteWith = Exception('db');
    await tester.tap(find.text(transferUndoLabel));
    await tester.pumpAndSettle();
    expect(find.text(transferUndoFailedText), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('list fits 360 dp at text scale $scale', (tester) async {
      final transfers = InMemoryTransfersRepository([
        transfer(
          't1',
          'a1',
          'a2',
          123456789,
          7,
          note: 'Очень длинный комментарий к переводу для проверки переноса',
        ),
        transfer('t2', 'a2', 'a1', 30000, 8),
      ]);
      await openAccount(
        tester,
        [acc('a1', 'Карта'), acc('a2', 'Очень длинное название счёта')],
        transfers,
        textScale: scale,
      );
      await tester.scrollUntilVisible(
        find.byKey(AccountTransfersList.rowKey('t1')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
