import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/date_chip.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';

final _today = DateOnly(2026, 9, 20);

/// Плашка внутри приложения с русской локалью. Выбор запоминается в [picked].
Widget _host({DateOnly? initial, required List<DateOnly> picked}) {
  var value = initial ?? _today;
  return MaterialApp(
    theme: AppTheme.light(),
    locale: MoneyApp.appLocale,
    supportedLocales: MoneyApp.supportedLocales,
    localizationsDelegates: MoneyApp.localizationsDelegates,
    home: Scaffold(
      body: Center(
        child: StatefulBuilder(
          builder: (context, setState) => DateChip(
            value: value,
            today: _today,
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

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  testWidgets('показывает «Сегодня» и «Вчера»', (tester) async {
    await tester.pumpWidget(_host(picked: []));
    expect(find.text('Сегодня'), findsOneWidget);

    await tester.pumpWidget(_host(initial: DateOnly(2026, 9, 19), picked: []));
    expect(find.text('Вчера'), findsOneWidget);
  });

  testWidgets('другой день показан датой словами', (tester) async {
    await tester.pumpWidget(_host(initial: DateOnly(2026, 9, 15), picked: []));
    expect(find.textContaining('15 сентября 2026'), findsOneWidget);
  });

  testWidgets('зона нажатия не меньше 48 dp', (tester) async {
    await tester.pumpWidget(_host(picked: []));
    final size = tester.getSize(find.byType(DateChip));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, greaterThanOrEqualTo(48));
  });

  testWidgets('подпись для скринридера: «Дата операции: сегодня»', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_host(picked: []));
    expect(find.bySemanticsLabel('Дата операции: сегодня'), findsOneWidget);

    await tester.pumpWidget(_host(initial: DateOnly(2026, 9, 19), picked: []));
    expect(find.bySemanticsLabel('Дата операции: вчера'), findsOneWidget);

    await tester.pumpWidget(_host(initial: DateOnly(2026, 9, 15), picked: []));
    expect(
      find.bySemanticsLabel(RegExp('Дата операции: 15 сентября 2026')),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('тап открывает русский календарь', (tester) async {
    await tester.pumpWidget(_host(picked: []));
    await tester.tap(find.byType(DateChip));
    await tester.pumpAndSettle();

    expect(find.text('Выберите дату'), findsOneWidget);
    expect(find.textContaining('сентябрь 2026'), findsOneWidget);
    expect(find.text('Отмена'), findsOneWidget);
    expect(find.text('ОК'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
  });

  testWidgets('выбор вчерашнего дня уходит наружу, плашка показывает «Вчера»', (
    tester,
  ) async {
    final picked = <DateOnly>[];
    await tester.pumpWidget(_host(picked: picked));
    await tester.tap(find.byType(DateChip));
    await tester.pumpAndSettle();

    await tester.tap(find.text('19'));
    await tester.tap(find.text('ОК'));
    await tester.pumpAndSettle();

    expect(picked, [DateOnly(2026, 9, 19)]);
    expect(find.text('Вчера'), findsOneWidget);
    expect(find.text('Сегодня'), findsNothing);
  });

  testWidgets('«Отмена» ничего не меняет', (tester) async {
    final picked = <DateOnly>[];
    await tester.pumpWidget(_host(picked: picked));
    await tester.tap(find.byType(DateChip));
    await tester.pumpAndSettle();

    await tester.tap(find.text('19'));
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(picked, isEmpty);
    expect(find.text('Сегодня'), findsOneWidget);
  });

  testWidgets('завтрашний день выбрать нельзя', (tester) async {
    final picked = <DateOnly>[];
    await tester.pumpWidget(_host(picked: picked));
    await tester.tap(find.byType(DateChip));
    await tester.pumpAndSettle();

    final calendar = tester.widget<CalendarDatePicker>(
      find.byType(CalendarDatePicker),
    );
    expect(calendar.lastDate, DateTime(2026, 9, 20));
    expect(calendar.firstDate, DateTime(2000));

    // Тап по 21-му числу не выбирает его: остаётся «сегодня».
    await tester.tap(find.text('21'));
    await tester.tap(find.text('ОК'));
    await tester.pumpAndSettle();

    expect(picked, [_today]);
    expect(find.text('Сегодня'), findsOneWidget);
  });
}
