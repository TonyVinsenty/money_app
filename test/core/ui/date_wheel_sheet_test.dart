import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/date_chip.dart';
import 'package:money_app/core/ui/date_wheel_sheet.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';

class _FixedClock extends Clock {
  _FixedClock(this._now);
  final DateTime _now;

  @override
  DateTime now() => _now;
}

final _clock = _FixedClock(DateTime(2026, 9, 20, 15));

/// Плашка даты; платформа задаётся в теме. Выбор копится в [picked].
Widget _host(TargetPlatform platform, List<DateOnly> picked) {
  var value = _clock.today();
  return MaterialApp(
    theme: AppTheme.light().copyWith(platform: platform),
    locale: MoneyApp.appLocale,
    supportedLocales: MoneyApp.supportedLocales,
    localizationsDelegates: MoneyApp.localizationsDelegates,
    home: Scaffold(
      body: Center(
        child: StatefulBuilder(
          builder: (context, setState) => DateChip(
            value: value,
            today: _clock.today(),
            onChanged: (day) {
              picked.add(day);
              setState(() => value = day);
            },
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(
  WidgetTester tester,
  TargetPlatform platform,
  List<DateOnly> picked,
) async {
  await tester.pumpWidget(_host(platform, picked));
  await tester.tap(find.byType(DateChip));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  testWidgets('iOS: лист с колесом даты, а не Material-календарь', (
    tester,
  ) async {
    await _open(tester, TargetPlatform.iOS, []);
    expect(find.byType(CupertinoDatePicker), findsOneWidget);
    expect(find.byType(CalendarDatePicker), findsNothing);
    expect(find.text(dateWheelDone), findsOneWidget);
    expect(find.text(dateWheelCancel), findsOneWidget);
  });

  testWidgets('iOS: границы колеса — с 2000 года и не позже сегодня', (
    tester,
  ) async {
    await _open(tester, TargetPlatform.iOS, []);
    final wheel = tester.widget<CupertinoDatePicker>(
      find.byType(CupertinoDatePicker),
    );
    expect(wheel.minimumDate, DateTime(2000));
    expect(wheel.maximumDate, DateTime(2026, 9, 20));
  });

  testWidgets('iOS: «Готово» без правок возвращает выбранный день', (
    tester,
  ) async {
    final picked = <DateOnly>[];
    await _open(tester, TargetPlatform.iOS, picked);
    await tester.tap(find.text(dateWheelDone));
    await tester.pumpAndSettle();
    expect(picked, [DateOnly(2026, 9, 20)]);
  });

  testWidgets('iOS: «Вчера» — вчера по Clock, «Готово» отдаёт его', (
    tester,
  ) async {
    final picked = <DateOnly>[];
    await _open(tester, TargetPlatform.iOS, picked);
    await tester.tap(find.widgetWithText(ActionChip, dateWheelYesterday));
    await tester.pumpAndSettle();
    await tester.tap(find.text(dateWheelDone));
    await tester.pumpAndSettle();
    expect(picked, [DateOnly(2026, 9, 19)]);
  });

  testWidgets('iOS: «Сегодня» возвращает на сегодня после «Вчера»', (
    tester,
  ) async {
    final picked = <DateOnly>[];
    await _open(tester, TargetPlatform.iOS, picked);
    await tester.tap(find.widgetWithText(ActionChip, dateWheelYesterday));
    await tester.pumpAndSettle();
    // «Сегодня» есть и на плашке под листом: берём чип внутри листа.
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(dateWheelToday),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(dateWheelDone));
    await tester.pumpAndSettle();
    expect(picked, [DateOnly(2026, 9, 20)]);
  });

  testWidgets('iOS: «Отмена» ничего не возвращает', (tester) async {
    final picked = <DateOnly>[];
    await _open(tester, TargetPlatform.iOS, picked);
    await tester.tap(find.widgetWithText(ActionChip, dateWheelYesterday));
    await tester.pumpAndSettle();
    await tester.tap(find.text(dateWheelCancel));
    await tester.pumpAndSettle();
    expect(picked, isEmpty);
    expect(find.byType(CupertinoDatePicker), findsNothing);
  });

  testWidgets('чип вне границ недоступен (начало диапазона — сегодня)', (
    tester,
  ) async {
    DateOnly? result;
    final today = _clock.today();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light().copyWith(platform: TargetPlatform.iOS),
        locale: MoneyApp.appLocale,
        supportedLocales: MoneyApp.supportedLocales,
        localizationsDelegates: MoneyApp.localizationsDelegates,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await pickDate(
              context,
              initial: today,
              first: today,
              last: DateOnly(9999, 12, 31),
              today: today,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final yesterday = tester.widget<ActionChip>(
      find.widgetWithText(ActionChip, dateWheelYesterday),
    );
    expect(yesterday.onPressed, isNull);
    final wheel = tester.widget<CupertinoDatePicker>(
      find.byType(CupertinoDatePicker),
    );
    expect(wheel.minimumDate, DateTime(2026, 9, 20));

    await tester.tap(find.text(dateWheelDone));
    await tester.pumpAndSettle();
    expect(result, today);
  });

  testWidgets('Android: по-прежнему Material-календарь', (tester) async {
    await _open(tester, TargetPlatform.android, []);
    expect(find.byType(CalendarDatePicker), findsOneWidget);
    expect(find.byType(CupertinoDatePicker), findsNothing);
    expect(find.text(dateWheelYesterday), findsNothing);
  });
}
