import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/balance_tab.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/ui/account_icons.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';
import 'package:money_app/features/accounts/presentation/accounts_section.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

import '../../../support/fakes.dart';

Money rub(int minor) => Money.fromMinor(minor, 'RUB');

Account acc(
  String id,
  String name, {
  String icon = 'card',
  String currency = 'RUB',
  bool archived = false,
  int order = 0,
}) => Account(
  id: id,
  name: name,
  iconKey: icon,
  openingBalance: Money.zero(currency),
  sortOrder: order,
  archivedAt: archived ? DateTime.utc(2026, 9, 1) : null,
);

Future<void> pumpSection(
  WidgetTester tester, {
  required Stream<List<Account>> accounts,
  required Stream<Map<String, Money>> balances,
  double scale = 1,
  VoidCallback? onAdd,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(360, 800),
          textScaler: TextScaler.linear(scale),
        ),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: AccountsSection(
              accounts: accounts,
              balances: balances,
              currency: 'RUB',
              onAddAccount: onAdd ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  testWidgets('нет счетов: подсказка и кнопка, «Всего» нет', (tester) async {
    var taps = 0;
    await pumpSection(
      tester,
      accounts: Stream.value(const []),
      balances: Stream.value(const {}),
      onAdd: () => taps++,
    );
    expect(find.text(accountsSectionTitle), findsOneWidget);
    expect(find.text(accountsEmptyText), findsOneWidget);
    expect(find.text(accountsTotalLabel), findsNothing);
    await tester.tap(find.text(accountsAddButton));
    expect(taps, 1);
  });

  testWidgets('один счёт: имя, остаток, «Всего» со знаком плюс', (
    tester,
  ) async {
    await pumpSection(
      tester,
      accounts: Stream.value([acc('a', 'Карта')]),
      balances: Stream.value({'a': rub(1200000)}),
    );
    expect(find.text('Карта'), findsOneWidget);
    expect(find.text(formatMoney(rub(1200000))), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(AccountsSection.totalKey)).data,
      '+${formatMoney(rub(1200000))}',
    );
    expect(find.text(accountsEmptyText), findsNothing);
    expect(find.byIcon(Icons.credit_card), findsOneWidget);
  });

  testWidgets('несколько счетов: порядок как в потоке, «Всего» — сумма', (
    tester,
  ) async {
    await pumpSection(
      tester,
      accounts: Stream.value([
        acc('a', 'Карта'),
        acc('b', 'Наличные', icon: 'cash', order: 1),
      ]),
      balances: Stream.value({'a': rub(1000), 'b': rub(550)}),
    );
    expect(
      tester.getTopLeft(find.text('Карта')).dy,
      lessThan(tester.getTopLeft(find.text('Наличные')).dy),
    );
    expect(
      tester.widget<Text>(find.byKey(AccountsSection.totalKey)).data,
      '+${formatMoney(rub(1550))}',
    );
  });

  testWidgets('минус: знак U+2212 и цвет расхода у счёта и у «Всего»', (
    tester,
  ) async {
    await pumpSection(
      tester,
      accounts: Stream.value([acc('a', 'Кредитка', icon: 'credit')]),
      balances: Stream.value({'a': rub(-150050)}),
    );
    const shown = '\u22121\u00A0500,50\u00A0\u20BD';
    expect(formatMoney(rub(-150050)), shown);
    final total = tester.widget<Text>(find.byKey(AccountsSection.totalKey));
    expect(total.data, shown);
    final expense = AppColors.light.expense;
    expect(total.style?.color, expense);
    final row = tester.widget<Text>(find.text(shown).last);
    expect(row.style?.color, expense);
  });

  testWidgets('архивные счета не видны и не входят во «Всего»', (tester) async {
    await pumpSection(
      tester,
      accounts: Stream.value([
        acc('a', 'Карта'),
        acc('b', 'Старый вклад', archived: true, order: 1),
      ]),
      balances: Stream.value({'a': rub(100), 'b': rub(99900)}),
    );
    expect(find.text('Старый вклад'), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(AccountsSection.totalKey)).data,
      '+${formatMoney(rub(100))}',
    );
  });

  testWidgets('только архивные счета — как пустой список', (tester) async {
    await pumpSection(
      tester,
      accounts: Stream.value([acc('b', 'Старый', archived: true)]),
      balances: Stream.value({'b': rub(5)}),
    );
    expect(find.text(accountsEmptyText), findsOneWidget);
    expect(find.text('Старый'), findsNothing);
  });

  testWidgets('ошибка потока: сообщение, без «Всего»', (tester) async {
    await pumpSection(
      tester,
      accounts: Stream.error(StateError('boom')),
      balances: Stream.value(const {}),
    );
    expect(find.text(accountsLoadError), findsOneWidget);
    expect(find.text(accountsTotalLabel), findsNothing);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('360 dp, шрифт ${scale * 100} %: без переполнения', (
      tester,
    ) async {
      await pumpSection(
        tester,
        scale: scale,
        accounts: Stream.value([
          acc('a', 'Накопительный счёт для большого отпуска'),
          acc('b', 'Кредитка', icon: 'credit', order: 1),
        ]),
        balances: Stream.value({'a': rub(123456789012), 'b': rub(-98765432)}),
      );
      expect(tester.takeException(), isNull);
      expect(find.byKey(AccountsSection.addButtonKey), findsOneWidget);
    });
  }

  testWidgets('семантика строки: имя и остаток; минус словом', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpSection(
      tester,
      accounts: Stream.value([
        acc('a', 'Карта'),
        acc('b', 'Кредитка', icon: 'credit', order: 1),
      ]),
      balances: Stream.value({'a': rub(1200000), 'b': rub(-5000)}),
    );
    expect(
      accountRowSemantics('Карта', rub(1200000)),
      'Карта, остаток 12000 рублей',
    );
    expect(
      find.bySemanticsLabel('Карта, остаток 12000 рублей'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Кредитка, остаток минус 50 рублей'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Всего на счетах: плюс 11950 рублей'),
      findsOneWidget,
    );
    handle.dispose();
  });

  group('значки счетов', () {
    test('8 ключей, неизвестный ключ — «Другое»', () {
      expect(accountIconOptions.map((o) => o.key).toList(), [
        'card',
        'cash',
        'wallet',
        'bank',
        'piggy',
        'deposit',
        'credit',
        'other',
      ]);
      expect(accountIconFor('card').label, 'Карта');
      expect(accountIconFor('nope').label, 'Другое');
      expect(accountIconFor('nope').icon, accountIconFor('other').icon);
    });
  });

  testWidgets('вкладка «Баланс» берёт счета из AppScope', (tester) async {
    final settings = AppSettingsController();
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: AppScope(
          services: fakeAppServices(
            settings: settings,
            accounts: FakeAccountsRepository(
              accounts: [acc('a', 'Карта')],
              balances: {'a': rub(100)},
            ),
          ),
          child: const Scaffold(body: BalanceTab()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Карта'), findsOneWidget);
    expect(find.text(accountsTotalLabel), findsOneWidget);
  });
}
