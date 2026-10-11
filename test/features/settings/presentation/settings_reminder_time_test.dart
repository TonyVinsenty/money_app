import 'package:flutter/cupertino.dart' show CupertinoDatePicker;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/recurring/domain/reminder_plan.dart';
import 'package:money_app/features/settings/domain/home_balance_line.dart';
import 'package:money_app/features/settings/presentation/settings_screen.dart';

void main() {
  Widget screen({
    ReminderTime? time,
    ValueChanged<ReminderTime>? onChanged,
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

  testWidgets('в группе «Учёт» после «Основная валюта», со значком', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(screen(onChanged: (_) {}));
    double top(String text) => tester.getTopLeft(find.text(text)).dy;

    expect(top(reminderTimeItemLabel), greaterThan(top('Основная валюта')));
    expect(top(reminderTimeItemLabel), lessThan(top('Данные')));
    expect(find.byIcon(Icons.notifications_none), findsOneWidget);
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

  group('iPhone: колесо (7.30f)', () {
    Future<void> openWheel(
      WidgetTester tester, {
      ValueChanged<ReminderTime>? onChanged,
      double textScale = 1,
    }) async {
      tester.view.physicalSize = const Size(400, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: screen(
            time: ReminderTime(9, 5),
            onChanged: onChanged,
            platform: TargetPlatform.iOS,
          ),
        ),
      );
      await tester.ensureVisible(find.text(reminderTimeItemLabel));
      await tester.tap(find.text(reminderTimeItemLabel));
      await tester.pumpAndSettle();
    }

    testWidgets('открывается колесо, а не циферблат', (tester) async {
      await openWheel(tester, onChanged: (_) {});
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      expect(find.byType(TimePickerDialog), findsNothing);
      final picker = tester.widget<CupertinoDatePicker>(
        find.byType(CupertinoDatePicker),
      );
      expect(picker.use24hFormat, isTrue);
      expect(picker.initialDateTime.hour, 9);
      expect(picker.initialDateTime.minute, 5);
      expect(find.text('Отмена'), findsOneWidget);
      expect(find.text('Готово'), findsOneWidget);
    });

    testWidgets('«Готово» сообщает выбранное время', (tester) async {
      final picked = <ReminderTime>[];
      await openWheel(tester, onChanged: picked.add);

      // Колесо часов вверх («9» без нуля только там; у минут — «09»). Часть
      // смещения съедает порог касания: колесо сдвигается на строку, 9 → 10.
      await tester.drag(find.text('9'), const Offset(0, -64));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();

      expect(picked.single.hour, 10);
      expect(picked.single.minute, 5);
      expect(find.byType(CupertinoDatePicker), findsNothing);
    });

    testWidgets('«Готово» без прокрутки — прежнее время', (tester) async {
      final picked = <ReminderTime>[];
      await openWheel(tester, onChanged: picked.add);
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();
      expect(picked, [ReminderTime(9, 5)]);
    });

    testWidgets('«Отмена» ничего не меняет', (tester) async {
      final picked = <ReminderTime>[];
      await openWheel(tester, onChanged: picked.add);
      await tester.drag(find.text('9'), const Offset(0, -64));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();
      expect(picked, isEmpty);
      expect(find.byType(CupertinoDatePicker), findsNothing);
    });

    testWidgets('шрифт 200 %: лист без переполнения', (tester) async {
      await openWheel(tester, onChanged: (_) {}, textScale: 2);
      expect(tester.takeException(), isNull);
      expect(find.byType(CupertinoDatePicker), findsOneWidget);
    });
  });

  testWidgets('Android: прежний циферблат', (tester) async {
    tester.view.physicalSize = const Size(400, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      screen(onChanged: (_) {}, platform: TargetPlatform.android),
    );
    await tester.ensureVisible(find.text(reminderTimeItemLabel));
    await tester.tap(find.text(reminderTimeItemLabel));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(find.byType(CupertinoDatePicker), findsNothing);
  });
}
