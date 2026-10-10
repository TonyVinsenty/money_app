import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/format/day_label.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/transfer.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';
import 'package:money_app/features/accounts/presentation/balance_journal_screen.dart';

final today = DateOnly(2026, 10, 10);

DateOnly utcDay(DateTime m) => DateOnly(m.year, m.month, m.day);

Account acc(
  String id,
  String name, {
  DateTime? createdAt,
  DateTime? archivedAt,
  String currency = 'RUB',
  int digits = 2,
}) => Account(
  id: id,
  name: name,
  iconKey: 'card',
  openingBalance: Money.zero(currency),
  sortOrder: 0,
  currencyDigits: digits,
  createdAt: createdAt,
  archivedAt: archivedAt,
);

Transfer transfer(
  String id,
  String from,
  String to,
  int minor,
  int day, {
  String currency = 'RUB',
  String? note,
}) => Transfer(
  id: id,
  fromAccountId: from,
  toAccountId: to,
  amount: Money.fromMinor(minor, currency),
  occurredOn: DateOnly(2026, 10, day),
  occurredAt: DateTime.utc(2026, 10, day, 9),
  note: note,
);

Future<void> pump(
  WidgetTester tester, {
  Stream<List<Account>>? accounts,
  Stream<List<Transfer>>? transfers,
  ValueChanged<Transfer>? onOpenTransfer,
  ValueChanged<Account>? onOpenAccount,
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
      home: BalanceJournalScreen(
        accounts: accounts ?? Stream.value(const []),
        transfers: transfers ?? Stream.value(const []),
        today: today,
        dayOf: utcDay,
        onOpenTransfer: onOpenTransfer,
        onOpenAccount: onOpenAccount,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  final created = DateTime.utc(2026, 10, 7, 10);
  final archived = DateTime.utc(2026, 10, 10, 10);
  final card = acc('a1', 'Карта', createdAt: created, archivedAt: archived);
  final cash = acc('a2', 'Наличные', createdAt: created);

  testWidgets('empty journal shows the empty text', (tester) async {
    await pump(tester);
    expect(find.text(balanceJournalTitle), findsOneWidget);
    expect(find.text(balanceJournalEmptyText), findsOneWidget);
  });

  testWidgets('three kinds of rows, day headers, partner in archive', (
    tester,
  ) async {
    await pump(
      tester,
      accounts: Stream.value([card, cash]),
      transfers: Stream.value([
        transfer('t1', 'a1', 'a2', 500000, 9, note: 'Аренда'),
      ]),
    );
    expect(find.text('Сегодня'), findsOneWidget);
    expect(find.text('Вчера'), findsOneWidget);
    expect(
      find.text(historyDayLabel(DateOnly(2026, 10, 7), today: today)),
      findsOneWidget,
    );
    expect(find.text(journalArchivedTitle('Карта')), findsOneWidget);
    expect(find.text(journalCreatedTitle('Карта')), findsOneWidget);
    expect(find.text(journalCreatedTitle('Наличные')), findsOneWidget);
    expect(find.text('Карта (в архиве) → Наличные'), findsOneWidget);
    expect(
      find.text(formatMoney(Money.fromMinor(500000, 'RUB'))),
      findsOneWidget,
    );
    expect(find.text('Аренда'), findsOneWidget);
  });

  testWidgets('spoken labels of all kinds', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(
      tester,
      accounts: Stream.value([card, cash]),
      transfers: Stream.value([
        transfer('t1', 'a1', 'a2', 500000, 9, note: 'Аренда'),
        transfer('t2', 'a2', 'a1', 100, 8),
      ]),
    );
    expect(
      find.bySemanticsLabel('Счёт Карта отправлен в архив, сегодня'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Создан счёт Наличные, 7 октября'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Перевод со счёта Карта (в архиве) на счёт Наличные, '
        '5000 рублей, вчера, комментарий: Аренда',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(
        'Перевод со счёта Наличные на счёт Карта (в архиве), 1 рубль, 8 октября',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('taps call the matching callbacks; null - not tappable', (
    tester,
  ) async {
    Transfer? openedTransfer;
    Account? openedAccount;
    final t = transfer('t1', 'a1', 'a2', 100, 9);
    await pump(
      tester,
      accounts: Stream.value([card, cash]),
      transfers: Stream.value([t]),
      onOpenTransfer: (v) => openedTransfer = v,
      onOpenAccount: (v) => openedAccount = v,
    );
    await tester.tap(find.text('Карта (в архиве) → Наличные'));
    expect(openedTransfer, t);
    await tester.tap(find.text(journalCreatedTitle('Наличные')));
    expect(openedAccount, cash);

    await pump(
      tester,
      accounts: Stream.value([card, cash]),
      transfers: Stream.value([t]),
    );
    expect(
      tester
          .widget<ListTile>(
            find.widgetWithText(ListTile, journalCreatedTitle('Наличные')),
          )
          .onTap,
      isNull,
    );
  });

  testWidgets('amounts in a custom currency with 4 digits and in BTC', (
    tester,
  ) async {
    final abc = acc('x1', 'Игры', currency: 'ABC', digits: 4);
    final abc2 = acc('x2', 'Склад', currency: 'ABC', digits: 4);
    final btc = acc('b1', 'Кошелёк', currency: 'BTC', digits: 8);
    final btc2 = acc('b2', 'Холод', currency: 'BTC', digits: 8);
    await pump(
      tester,
      accounts: Stream.value([abc, abc2, btc, btc2]),
      transfers: Stream.value([
        transfer('t1', 'x1', 'x2', 12345, 9, currency: 'ABC'),
        transfer('t2', 'b1', 'b2', 99999999999, 9, currency: 'BTC'),
      ]),
    );
    expect(
      find.text(
        formatMoney(Money.fromMinor(12345, 'ABC'), currency: abc.currencyInfo),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        formatMoney(
          Money.fromMinor(99999999999, 'BTC'),
          currency: btc.currencyInfo,
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('stream error shows the error text, screen stays alive', (
    tester,
  ) async {
    await pump(
      tester,
      accounts: Stream.value([card]),
      transfers: Stream.error(StateError('boom')),
    );
    expect(find.text(balanceJournalLoadError), findsOneWidget);
    expect(find.text(balanceJournalTitle), findsOneWidget);
  });

  testWidgets('loading shows a progress indicator', (tester) async {
    final never = StreamController<List<Account>>();
    addTearDown(never.close);
    await pump(tester, accounts: never.stream);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('200% font and long names: no overflow', (tester) async {
    final long = 'Очень длинное название счёта ' * 2;
    final a = acc('a1', long.substring(0, 40), createdAt: created);
    final b = acc('a2', long.substring(10, 50), createdAt: created);
    final big = acc('big', 'BTC', currency: 'BTC', digits: 8);
    final big2 = acc('big2', 'BTC 2', currency: 'BTC', digits: 8);
    await pump(
      tester,
      accounts: Stream.value([a, b, big, big2]),
      transfers: Stream.value([
        transfer('t1', 'a1', 'a2', 99999999, 9, note: long),
        transfer('t2', 'big', 'big2', 99999999999999, 9, currency: 'BTC'),
      ]),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
  });
}
