import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/recurring/domain/reminder_plan.dart';
import 'package:money_app/features/settings/domain/home_balance_line.dart';
import 'package:money_app/features/settings/presentation/settings_screen.dart';

void main() {
  Widget screen({ReminderTime? time, ValueChanged<ReminderTime>? onChanged}) =>
      MaterialApp(
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
            today: DateOnly(2026, 10, 10),
            onExportShared: () {},
            onImportCsv: () async => null,
            onClearAll: () async {},
            version: '0.1.0+20',
            reminderTime: time,
            onReminderTimeChanged: onChanged,
          ),
        ),
      );

  testWidgets('без обработчика пункта «Время напоминаний» нет', (tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(screen());
    expect(find.text(reminderTimeItemLabel), findsNothing);
  });

  testWidgets('строка показывает ЧЧ:ММ, выбор времени сообщает наружу', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ReminderTime? picked;
    await tester.pumpWidget(
      screen(time: ReminderTime(9, 5), onChanged: (t) => picked = t),
    );
    expect(find.text(reminderTimeItemLabel), findsOneWidget);
    expect(find.text('09:05'), findsOneWidget);

    await tester.ensureVisible(find.text(reminderTimeItemLabel));
    await tester.tap(find.text(reminderTimeItemLabel));
    await tester.pumpAndSettle();
    // Диалог времени открыт; подтверждаем выбранное время.
    expect(find.byType(TimePickerDialog), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(picked, ReminderTime(9, 5));
  });

  testWidgets('отмена выбора времени ничего не меняет', (tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    ReminderTime? picked;
    await tester.pumpWidget(
      screen(time: ReminderTime(9, 5), onChanged: (t) => picked = t),
    );
    await tester.ensureVisible(find.text(reminderTimeItemLabel));
    await tester.tap(find.text(reminderTimeItemLabel));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });
}
