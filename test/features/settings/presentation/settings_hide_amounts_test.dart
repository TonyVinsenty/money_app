import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/settings/domain/home_balance_line.dart';
import 'package:money_app/features/settings/presentation/settings_screen.dart';

import '../../../support/adaptive_switch.dart';

void main() {
  Widget screen({
    bool hide = false,
    ValueChanged<bool>? onChanged,
    TargetPlatform? platform,
  }) => MaterialApp(
    theme: ThemeData(platform: platform),
    home: Scaffold(
      body: SettingsScreen(
        themeMode: ThemeMode.system,
        onThemeModeChanged: (_) {},
        homeBalanceLine: HomeBalanceLine.allTime,
        onHomeBalanceLineChanged: (_) {},
        onOpenCategories: () {},
        mainCurrency: currencyInfoFor('RUB'),
        onMainCurrencyChanged: (_) {},
        onExportCsv: () async => '',
        lastExportDay: null,
        today: DateOnly(2026, 10, 12),
        onExportShared: () {},
        onImportCsv: () async => null,
        onClearAll: () async {},
        version: '0.1.0+24',
        hideAmounts: hide,
        onHideAmountsChanged: onChanged,
      ),
    ),
  );

  testWidgets('без обработчика переключателя нет', (tester) async {
    await tester.pumpWidget(screen());
    expect(find.text(hideAmountsLabel), findsNothing);
  });

  testWidgets('в группе «Внешний вид» после «Тема», со значком', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(screen(onChanged: (_) {}));
    double top(String text) => tester.getTopLeft(find.text(text)).dy;

    expect(top(hideAmountsLabel), greaterThan(top('Тёмная')));
    expect(top(hideAmountsLabel), lessThan(top('Кольцо на «Главной»')));
    expect(
      find.descendant(
        of: find.widgetWithText(SwitchListTile, hideAmountsLabel),
        matching: find.byIcon(Icons.visibility_off_outlined),
      ),
      findsOneWidget,
    );
  });

  testWidgets('переключатель показывает значение и сообщает наружу', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    bool? changed;
    await tester.pumpWidget(screen(onChanged: (v) => changed = v));
    final tile = find.widgetWithText(SwitchListTile, hideAmountsLabel);
    expect(tester.widget<SwitchListTile>(tile).value, isFalse);

    await tester.tap(tile);
    expect(changed, isTrue);

    await tester.pumpWidget(screen(hide: true, onChanged: (v) => changed = v));
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    await tester.tap(tile);
    expect(changed, isFalse);
  });

  for (final (platform, ios) in [
    (TargetPlatform.iOS, true),
    (TargetPlatform.android, false),
  ]) {
    testWidgets('$platform: переключатель по-айфонному — $ios', (tester) async {
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      bool? changed;
      await tester.pumpWidget(
        screen(onChanged: (v) => changed = v, platform: platform),
      );
      final tile = find.widgetWithText(SwitchListTile, hideAmountsLabel);
      expect(
        find.descendant(of: tile, matching: find.byType(Switch)),
        ios ? paintsIosSwitchTrack : paintsMaterialSwitchTrack,
      );
      await tester.tap(tile);
      expect(changed, isTrue);
    });
  }
}
