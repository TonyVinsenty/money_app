import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/browse_controller.dart';
import 'package:money_app/app/browse_scope.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/domain/history_view.dart';

import '../support/fakes.dart';

/// Смена основной валюты сбрасывает ручной фильтр по счёту (5.15m).
void main() {
  late AppSettingsController settings;
  late BrowseController browse;

  Future<void> pump(WidgetTester tester) async {
    settings = AppSettingsController();
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: AppScope(
          services: fakeAppServices(settings: settings),
          child: BrowseHost(
            child: Builder(
              builder: (context) {
                browse = BrowseScope.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('«Счёт: Карта»: после смены валюты счёта нет, остальное есть', (
    tester,
  ) async {
    await pump(tester);
    browse.setHistoryFilter(
      HistoryFilter(
        type: HistoryTypeFilter.expense,
        expenseCategoryIds: {'food'},
        accountFilter: const OneAccount('card'),
      ),
    );
    await tester.pump();

    await settings.setMainCurrency(catalogCurrency('USD')!);
    await tester.pump();

    expect(
      browse.historyFilter,
      HistoryFilter(
        type: HistoryTypeFilter.expense,
        expenseCategoryIds: {'food'},
      ),
    );
  });

  testWidgets('«Без счёта» тоже сбрасывается', (tester) async {
    await pump(tester);
    browse.setHistoryFilter(
      HistoryFilter(
        type: HistoryTypeFilter.income,
        accountFilter: const NoAccount(),
      ),
    );
    await tester.pump();

    await settings.setMainCurrency(catalogCurrency('USD')!);
    await tester.pump();

    expect(browse.historyFilter, HistoryFilter(type: HistoryTypeFilter.income));
  });

  testWidgets('без смены валюты фильтр по счёту остаётся', (tester) async {
    await pump(tester);
    browse.setHistoryFilter(HistoryFilter.account('card'));
    await tester.pump();

    await settings.setMainCurrency(catalogCurrency('RUB')!);
    await tester.pump();

    expect(browse.historyFilter, HistoryFilter.account('card'));
  });
}
