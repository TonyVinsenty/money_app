import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/balance_tab.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/transfer.dart';
import 'package:money_app/features/accounts/presentation/account_screen.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';
import 'package:money_app/features/accounts/presentation/accounts_section.dart';
import 'package:money_app/features/accounts/presentation/transfer_form_screen.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

import '../../../support/fake_id_generator.dart';
import '../../../support/fakes.dart';
import '../../../support/fixed_clock.dart';

Account acc(
  String id,
  String name, {
  String currency = 'RUB',
  bool archived = false,
}) => Account(
  id: id,
  name: name,
  iconKey: 'card',
  openingBalance: Money.zero(currency),
  sortOrder: 0,
  currencyDigits: 2,
  archivedAt: archived ? DateTime.utc(2026, 9, 1) : null,
);

final clock = FixedClock(DateTime.utc(2026, 9, 20, 12));

Future<void> pumpForm(
  WidgetTester tester,
  InMemoryAccountsRepository accounts,
  InMemoryTransfersRepository transfers, {
  String? fromAccountId,
  Transfer? editing,
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
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => TransferFormScreen(
                    accounts: accounts.watchAll(),
                    transfers: transfers,
                    idGenerator: FakeIdGenerator(prefix: 't'),
                    clock: clock,
                    fromAccountId: fromAccountId,
                    editing: editing,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> pick(WidgetTester tester, Key field, String name) async {
  await tester.tap(find.byKey(field));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester) async {
  await tester.tap(find.byKey(TransferFormScreen.saveKey));
  await tester.pumpAndSettle();
}

DropdownButtonFormField<String> dropdown(WidgetTester tester, Key field) =>
    tester.widget(
      find.descendant(
        of: find.byKey(field),
        matching: find.byType(DropdownButtonFormField<String>),
      ),
    );

List<String?> optionIds(WidgetTester tester, Key field) => tester
    .widget<DropdownButton<String>>(
      find.descendant(
        of: find.byKey(field),
        matching: find.byType(DropdownButton<String>),
      ),
    )
    .items!
    .map((i) => i.value)
    .toList();

List<Account> threeRub() => [
  acc('a1', 'Карта'),
  acc('a2', 'Наличные'),
  acc('a3', 'Копилка'),
];

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('saves a transfer and shows SnackBar with undo', (tester) async {
    final transfers = InMemoryTransfersRepository();
    await pumpForm(tester, InMemoryAccountsRepository(threeRub()), transfers);
    expect(find.text(transferFormCreateTitle), findsOneWidget);

    await pick(tester, TransferFormScreen.toKey, 'Наличные');
    await tester.enterText(find.byKey(TransferFormScreen.amountKey), '5000');
    await tester.enterText(
      find.byKey(TransferFormScreen.noteKey),
      ' Зарплата ',
    );
    await save(tester);

    expect(transfers.all, hasLength(1));
    final t = transfers.all.single;
    expect(t.id, 't-1');
    expect(t.fromAccountId, 'a1');
    expect(t.toAccountId, 'a2');
    expect(t.amount, Money.fromMinor(500000, 'RUB'));
    expect(t.note, 'Зарплата');
    expect(t.occurredOn, DateOnly(2026, 9, 20));
    expect(t.occurredAt, clock.now());
    final text = 'Перевод ${formatMoney(t.amount)}: Карта → Наличные';
    expect(find.text(text), findsOneWidget);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('undo removes the saved transfer', (tester) async {
    final transfers = InMemoryTransfersRepository();
    await pumpForm(tester, InMemoryAccountsRepository(threeRub()), transfers);
    await pick(tester, TransferFormScreen.toKey, 'Наличные');
    await tester.enterText(find.byKey(TransferFormScreen.amountKey), '100');
    await save(tester);
    expect(transfers.all, hasLength(1));

    await tester.tap(find.text(transferUndoLabel));
    await tester.pumpAndSettle();
    expect(transfers.all, isEmpty);
  });

  testWidgets('empty amount and zero show errors under the field', (
    tester,
  ) async {
    final transfers = InMemoryTransfersRepository();
    await pumpForm(tester, InMemoryAccountsRepository(threeRub()), transfers);
    await pick(tester, TransferFormScreen.toKey, 'Наличные');

    await save(tester);
    expect(find.text('Введите сумму'), findsOneWidget);

    await tester.enterText(find.byKey(TransferFormScreen.amountKey), '0');
    await save(tester);
    expect(find.text(transferZeroAmountText), findsOneWidget);
    expect(find.text('Введите сумму'), findsNothing);
    expect(transfers.all, isEmpty);

    await tester.enterText(find.byKey(TransferFormScreen.amountKey), '1');
    await tester.pump();
    expect(find.text(transferZeroAmountText), findsNothing);
  });

  testWidgets('no target chosen shows the message', (tester) async {
    final transfers = InMemoryTransfersRepository();
    await pumpForm(tester, InMemoryAccountsRepository(threeRub()), transfers);
    await tester.enterText(find.byKey(TransferFormScreen.amountKey), '100');
    await save(tester);
    expect(find.text(transferToMissingText), findsOneWidget);
    expect(transfers.all, isEmpty);

    await pick(tester, TransferFormScreen.toKey, 'Копилка');
    expect(find.text(transferToMissingText), findsNothing);
  });

  testWidgets('target list has no source, archived or other currency', (
    tester,
  ) async {
    final accounts = InMemoryAccountsRepository([
      ...threeRub(),
      acc('a4', 'Старая', archived: true),
      acc('a5', 'Доллары', currency: 'USD'),
    ]);
    await pumpForm(tester, accounts, InMemoryTransfersRepository());
    expect(optionIds(tester, TransferFormScreen.toKey), ['a2', 'a3']);
    expect(optionIds(tester, TransferFormScreen.fromKey), [
      'a1',
      'a2',
      'a3',
      'a5',
    ]);
  });

  testWidgets('changing source to another currency resets target', (
    tester,
  ) async {
    final accounts = InMemoryAccountsRepository([
      ...threeRub(),
      acc('a5', 'Доллары', currency: 'USD'),
      acc('a6', 'Копилка USD', currency: 'USD'),
    ]);
    await pumpForm(tester, accounts, InMemoryTransfersRepository());
    await pick(tester, TransferFormScreen.toKey, 'Наличные');
    expect(dropdown(tester, TransferFormScreen.toKey).initialValue, 'a2');
    await tester.enterText(find.byKey(TransferFormScreen.amountKey), '5');

    await pick(tester, TransferFormScreen.fromKey, 'Доллары');
    expect(dropdown(tester, TransferFormScreen.toKey).initialValue, isNull);
    expect(optionIds(tester, TransferFormScreen.toKey), ['a6']);
    expect(find.text(r'$'), findsOneWidget);
  });

  testWidgets('foreign currency amount is saved in that currency', (
    tester,
  ) async {
    final transfers = InMemoryTransfersRepository();
    final accounts = InMemoryAccountsRepository([
      acc('a5', 'Доллары', currency: 'USD'),
      acc('a6', 'Копилка USD', currency: 'USD'),
    ]);
    await pumpForm(tester, accounts, transfers);
    await pick(tester, TransferFormScreen.toKey, 'Копилка USD');
    await tester.enterText(find.byKey(TransferFormScreen.amountKey), '12,5');
    await save(tester);
    expect(transfers.all.single.amount, Money.fromMinor(1250, 'USD'));
  });

  testWidgets('write failure shows the common message and stays open', (
    tester,
  ) async {
    final transfers = InMemoryTransfersRepository()..failWith = Exception('db');
    await pumpForm(tester, InMemoryAccountsRepository(threeRub()), transfers);
    await pick(tester, TransferFormScreen.toKey, 'Наличные');
    await tester.enterText(find.byKey(TransferFormScreen.amountKey), '100');
    await save(tester);
    expect(find.text(transferSaveFailedText), findsOneWidget);
    expect(find.text(transferFormCreateTitle), findsOneWidget);
  });

  testWidgets('edit mode fills the form and updates the transfer', (
    tester,
  ) async {
    final old = Transfer(
      id: 'old',
      fromAccountId: 'a1',
      toAccountId: 'a4',
      amount: Money.fromMinor(150050, 'RUB'),
      occurredOn: DateOnly(2026, 9, 10),
      occurredAt: DateTime.utc(2026, 9, 10, 9),
      note: 'было',
    );
    final transfers = InMemoryTransfersRepository([old]);
    final accounts = InMemoryAccountsRepository([
      ...threeRub(),
      acc('a4', 'Старая', archived: true),
    ]);
    await pumpForm(tester, accounts, transfers, editing: old);
    expect(find.text(transferFormEditTitle), findsOneWidget);
    expect(find.text(transferArchivedAccountName('Старая')), findsOneWidget);
    expect(find.text('было'), findsOneWidget);

    await tester.enterText(find.byKey(TransferFormScreen.amountKey), '2000');
    await save(tester);
    final t = transfers.all.single;
    expect(t.id, 'old');
    expect(t.amount, Money.fromMinor(200000, 'RUB'));
    expect(t.occurredAt, old.occurredAt);
    expect(find.text(transferEditSavedText), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('fits 360 dp at text scale $scale', (tester) async {
      const longTo = 'Ещё одно довольно длинное название счёта';
      final accounts = InMemoryAccountsRepository([
        acc('a1', 'Очень длинное название карты для теста'),
        acc('a2', longTo),
      ]);
      await pumpForm(
        tester,
        accounts,
        InMemoryTransfersRepository(),
        textScale: scale,
      );
      await pick(tester, TransferFormScreen.toKey, longTo);
      await tester.enterText(
        find.byKey(TransferFormScreen.amountKey),
        '1234567',
      );
      await save(tester);
      expect(tester.takeException(), isNull);
    });
  }

  group('buttons', () {
    Future<void> pumpTab(WidgetTester tester, List<Account> list) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final settings = AppSettingsController();
      addTearDown(settings.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          onGenerateRoute: onGenerateAppRoute,
          home: AppScope(
            services: fakeAppServices(
              settings: settings,
              accounts: InMemoryAccountsRepository(list),
              transfers: InMemoryTransfersRepository(),
              clock: clock,
            ),
            child: const Scaffold(body: BalanceTab()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    testWidgets('hidden with one account', (tester) async {
      await pumpTab(tester, [acc('a1', 'Карта')]);
      expect(find.byKey(AccountsSection.transferKey), findsNothing);
    });

    testWidgets('hidden without a same-currency pair', (tester) async {
      await pumpTab(tester, [
        acc('a1', 'Карта'),
        acc('a5', 'Доллары', currency: 'USD'),
      ]);
      expect(find.byKey(AccountsSection.transferKey), findsNothing);
    });

    testWidgets('hidden when the pair is archived', (tester) async {
      await pumpTab(tester, [
        acc('a1', 'Карта'),
        acc('a2', 'Старая', archived: true),
      ]);
      expect(find.byKey(AccountsSection.transferKey), findsNothing);
    });

    testWidgets('tab button opens the form', (tester) async {
      await pumpTab(tester, [acc('a1', 'Карта'), acc('a2', 'Наличные')]);
      await tester.tap(find.byKey(AccountsSection.transferKey));
      await tester.pumpAndSettle();
      expect(find.text(transferFormCreateTitle), findsOneWidget);
      expect(dropdown(tester, TransferFormScreen.fromKey).initialValue, 'a1');
    });

    testWidgets('account screen button sets the source', (tester) async {
      await pumpTab(tester, [
        acc('a1', 'Карта'),
        acc('a2', 'Наличные'),
        acc('a5', 'Доллары', currency: 'USD'),
      ]);
      await tester.tap(find.text('Доллары'));
      await tester.pumpAndSettle();
      expect(find.byKey(AccountScreen.transferKey), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Наличные'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(AccountScreen.transferKey));
      await tester.pumpAndSettle();
      expect(find.text(transferFormCreateTitle), findsOneWidget);
      expect(dropdown(tester, TransferFormScreen.fromKey).initialValue, 'a2');
    });
  });
}
