import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

import '../support/in_memory_database.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  testWidgets('showDatePicker показывает русские строки', (tester) async {
    final settings = AppSettingsController();
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MoneyApp(settings: settings, openDatabase: openInMemoryDatabase),
    );
    // Первый кадр — загрузка; второй — база открылась, показаны вкладки.
    await tester.pump();

    // Результат нам не нужен: проверяем только, что нарисовал диалог.
    unawaited(
      showDatePicker(
        context: tester.element(find.byType(Scaffold)),
        initialDate: DateTime(2026, 9, 19),
        firstDate: DateTime(2020),
        lastDate: DateTime(2030),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Выберите дату'), findsOneWidget);
    // Между годом и «г.» стоит неразрывный пробел, поэтому ищем по началу.
    expect(find.textContaining('сентябрь 2026'), findsOneWidget);
    expect(find.text('Отмена'), findsOneWidget);
    expect(find.text('ОК'), findsOneWidget);
    expect(find.text('Cancel'), findsNothing);
    expect(find.text('OK'), findsNothing);
  });

  test('после initializeDateFormatting("ru") месяц пишется по-русски', () {
    final formatted = DateFormat.yMMMMd('ru').format(DateTime(2026, 9, 19));

    expect(formatted, contains('сентября'));
  });
}
