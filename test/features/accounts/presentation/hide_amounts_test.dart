import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/balance_tab.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/ui/masked_amount.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/presentation/account_screen.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

import '../../../support/fakes.dart';

const _cloud = ValueKey('masked-amount-cloud');

Money rub(int minor) => Money.fromMinor(minor, 'RUB');

final _account = Account(
  id: 'a',
  name: 'Карта',
  iconKey: 'card',
  openingBalance: rub(1234567),
  sortOrder: 0,
  currencyDigits: 2,
);

Future<void> _pumpTab(WidgetTester tester, {required bool hidden}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = AppSettingsController();
  addTearDown(settings.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      onGenerateRoute: onGenerateAppRoute,
      builder: (context, child) =>
          AmountsVisibility(hidden: hidden, child: child!),
      home: AppScope(
        services: fakeAppServices(
          settings: settings,
          accounts: InMemoryAccountsRepository([_account]),
        ),
        child: const Scaffold(body: BalanceTab()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// Весь видимый текст экрана одной строкой.
String _allText(WidgetTester tester) =>
    [for (final t in tester.widgetList<Text>(find.byType(Text))) t.data ?? '']
        .join('|');

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  final shown = formatMoney(rub(1234567));

  testWidgets('«Баланс» видно: суммы счёта и «Всего» на месте', (tester) async {
    await _pumpTab(tester, hidden: false);
    // Остаток счёта и «Всего» - один текст без «+».
    expect(find.text(shown), findsNWidgets(2));
    expect(find.byKey(_cloud), findsNothing);
  });

  testWidgets('«Баланс» скрыто: суммы счёта и «Всего» в облачках', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpTab(tester, hidden: true);
    expect(_allText(tester), isNot(contains('345,67')));
    expect(find.text('Карта'), findsOneWidget);
    expect(find.byKey(_cloud), findsNWidgets(2));
    expect(
      find.bySemanticsLabel('Карта, остаток $hiddenAmountLabel'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('$accountsTotalLabel: $hiddenAmountLabel'),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('экран счёта скрыто: остаток в облачке, видимый - как раньше', (
    tester,
  ) async {
    await _pumpTab(tester, hidden: false);
    await tester.tap(find.text('Карта'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(find.byKey(AccountScreen.balanceKey)).data,
      shown,
    );

    await _pumpTab(tester, hidden: true);
    await tester.tap(find.text('Карта'));
    await tester.pumpAndSettle();
    expect(find.byKey(AccountScreen.balanceKey), findsNothing);
    expect(_allText(tester), isNot(contains('345,67')));
    expect(find.byKey(_cloud), findsOneWidget);
  });

  group('тексты счетов с hidden', () {
    final info = currencyInfoFor('RUB');
    final amount = rub(500000);
    final noDigits = isNot(contains(RegExp(r'\d{3}')));

    test('диалог архива', () {
      expect(accountArchiveDialogText(amount, info), contains('5'));
      final hiddenText = accountArchiveDialogText(amount, info, hidden: true);
      expect(hiddenText, startsWith('На счёте $maskedMoneyText.'));
      expect(hiddenText, noDigits);
    });

    test('«Всего» и строка счёта', () {
      expect(
        accountsTotalSpoken(amount, info, hidden: true),
        hiddenAmountLabel,
      );
      expect(
        accountsTotalSemantics([(amount, info)], hidden: true),
        '$accountsTotalLabel: $hiddenAmountLabel',
      );
      expect(
        accountRowSemantics('Карта', amount, info, hidden: true),
        'Карта, остаток $hiddenAmountLabel',
      );
    });

    test('переводы', () {
      expect(
        transferRowAmount(true, amount, info, hidden: true),
        maskedMoneyText,
      );
      expect(
        transferRowSpoken(
          true,
          'Наличные',
          amount,
          info,
          '7 октября',
          hidden: true,
        ),
        'Перевод на счёт Наличные, $hiddenAmountLabel, 7 октября',
      );
      expect(
        transferRowSpoken(
          false,
          'Карта',
          amount,
          info,
          '7 октября',
          hidden: true,
        ),
        'Перевод со счёта Карта, $hiddenAmountLabel, 7 октября',
      );
      expect(
        journalTransferSpoken(
          'Карта',
          'Наличные',
          amount,
          info,
          '7 октября',
          hidden: true,
        ),
        'Перевод со счёта Карта на счёт Наличные, $hiddenAmountLabel, '
        '7 октября',
      );
    });

    test('без hidden суммы видны', () {
      expect(transferRowAmount(false, amount, info), startsWith('+'));
      expect(
        accountRowSemantics('Карта', amount, info),
        isNot(contains(hiddenAmountLabel)),
      );
    });
  });

  testWidgets('MaskedAmount: textKey виден только без скрытия', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const AmountsVisibility(
          hidden: false,
          child: Scaffold(body: MaskedAmount('1', textKey: Key('t'))),
        ),
      ),
    );
    expect(find.byKey(const Key('t')), findsOneWidget);
  });
}
