import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/app_tabs.dart';
import 'package:money_app/app/browse_scope.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/presentation/quick_add/account_chip.dart';

import '../support/fakes.dart';

/// «Главная» -> «Расход»: поток счетов и основной счёт доходят до плашки.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  testWidgets('основной счёт из настроек стоит на плашке быстрого ввода', (
    tester,
  ) async {
    final settings = AppSettingsController();
    addTearDown(settings.dispose);
    await settings.setDefaultAccountId('a');
    final repo = InMemoryAccountsRepository([
      Account(
        id: 'a',
        name: 'Карта',
        iconKey: 'card',
        openingBalance: Money.zero('RUB'),
        sortOrder: 0,
        currencyDigits: 2,
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        onGenerateRoute: onGenerateAppRoute,
        home: AppScope(
          services: fakeAppServices(settings: settings, accounts: repo),
          child: const BrowseHost(child: Scaffold(body: HomeActions())),
        ),
      ),
    );
    await tester.tap(find.text('Расход'));
    await tester.pumpAndSettle();
    expect(find.byKey(AccountChip.chipKey), findsOneWidget);
    expect(find.text('Карта'), findsOneWidget);
  });
}
