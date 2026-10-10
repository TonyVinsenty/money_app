import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/app_tabs.dart';
import 'package:money_app/app/browse_scope.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/donut_chart.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/settings/domain/home_balance_line.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../support/fakes.dart';
import '../support/fixed_clock.dart';

/// Итоги «за всё время» заданы числами; операций месяца нет.
class _Repo extends FakeTransactionsRepository {
  _Repo({required this.income, required this.expense});

  final Map<String, int> income;
  final Map<String, int> expense;

  @override
  Stream<Money> watchTotal({
    required TransactionType type,
    required DateRange period,
    String currency = 'RUB',
  }) {
    final minor = (type == TransactionType.income ? income : expense)[currency];
    return Stream.value(Money.fromMinor(minor ?? 0, currency));
  }

  @override
  Stream<List<Transaction>> watchInPeriod(
    DateRange period, {
    String currency = 'RUB',
  }) => Stream.value(const []);
}

Account _account(String id, String currency, int opening) => Account(
  id: id,
  name: 'Счёт $id',
  iconKey: 'wallet',
  openingBalance: Money.fromMinor(opening, currency),
  sortOrder: 0,
  currencyDigits: 2,
);

String _line(int minor, [String code = 'RUB']) {
  final money = Money.fromMinor(minor, code);
  return 'Баланс: ${minor > 0 ? '+' : ''}${formatMoney(money)}';
}

Future<AppSettingsController> _pump(
  WidgetTester tester, {
  required _Repo repo,
  required InMemoryAccountsRepository accounts,
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = AppSettingsController();
  addTearDown(settings.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: MoneyApp.appLocale,
      supportedLocales: MoneyApp.supportedLocales,
      localizationsDelegates: MoneyApp.localizationsDelegates,
      home: AppScope(
        services: fakeAppServices(
          settings: settings,
          categories: InMemoryCategoriesRepository(const []),
          transactions: repo,
          accounts: accounts,
          clock: FixedClock(DateTime(2026, 10, 4, 12)),
        ),
        child: BrowseHost(child: const Scaffold(body: HomeTab())),
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
  return settings;
}

Finder get _inRing =>
    find.descendant(of: find.byType(DonutChart), matching: find.byType(Text));

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('по умолчанию - все доходы минус все расходы', (tester) async {
    final repo = _Repo(income: {'RUB': 1000000}, expense: {'RUB': 250000});
    await _pump(tester, repo: repo, accounts: InMemoryAccountsRepository());

    expect(find.text(_line(750000)), findsOneWidget);
  });

  testWidgets('смена настройки на лету: счета, «Не показывать», обратно', (
    tester,
  ) async {
    final repo = _Repo(income: {'RUB': 1000000}, expense: {'RUB': 250000});
    final accounts = InMemoryAccountsRepository([
      _account('a', 'RUB', 300000),
      _account('b', 'USD', 99),
    ]);
    final settings = await _pump(tester, repo: repo, accounts: accounts);
    expect(find.text(_line(750000)), findsOneWidget);

    settings.setHomeBalanceLine(HomeBalanceLine.accounts);
    await _settle(tester);
    expect(find.text(_line(300000)), findsOneWidget);
    expect(find.text(_line(750000)), findsNothing);

    settings.setHomeBalanceLine(HomeBalanceLine.none);
    await _settle(tester);
    expect(find.textContaining('Баланс'), findsNothing);
    expect(_inRing, findsWidgets);

    settings.setHomeBalanceLine(HomeBalanceLine.allTime);
    await _settle(tester);
    expect(find.text(_line(750000)), findsOneWidget);
  });

  testWidgets('«Сумма на счетах»: счетов основной валюты нет - строки нет', (
    tester,
  ) async {
    final repo = _Repo(income: {'RUB': 5}, expense: {});
    final accounts = InMemoryAccountsRepository([_account('b', 'USD', 99)]);
    final settings = await _pump(tester, repo: repo, accounts: accounts);

    settings.setHomeBalanceLine(HomeBalanceLine.accounts);
    await _settle(tester);

    expect(find.textContaining('Баланс'), findsNothing);
  });

  testWidgets('смена основной валюты перестраивает строку', (tester) async {
    final repo = _Repo(
      income: {'RUB': 1000, 'USD': 777},
      expense: {'RUB': 0, 'USD': 0},
    );
    final settings = await _pump(
      tester,
      repo: repo,
      accounts: InMemoryAccountsRepository(),
    );
    expect(find.text(_line(1000)), findsOneWidget);

    await settings.setMainCurrency(catalogCurrency('USD')!);
    await _settle(tester);

    expect(find.text(_line(777, 'USD')), findsOneWidget);
  });
}
