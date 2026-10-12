import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';

import '../support/extreme_app.dart';
import '../support/extreme_data.dart';
import '../support/settle_database.dart';

/// Шаг 7.43 (К2): «Главная», «История» и четыре раздела «Аналитики» на
/// наборе крайних данных, телефон 360 dp, шрифт 100 и 200 %: ни переполнений,
/// ни исключений, в том числе при прокрутке до конца.
final _maxRub = formatMoney(Money.fromMinor(extremeMaxRubMinor, 'RUB'));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  for (final scale in [1.0, 2.0]) {
    final percent = '${(scale * 100).round()} %';

    testWidgets('«Главная», $percent', (tester) async {
      await pumpExtremeApp(tester, scale);
      // Набор действительно на экране: плашка платежа на сегодня.
      expect(find.textContaining('К оплате'), findsWidgets);
      await scrollThrough(tester, 'Главная');
    });

    testWidgets('«История», $percent', (tester) async {
      await pumpExtremeApp(tester, scale);
      await openExtremeTab(tester, 'История');
      expect(find.textContaining('Коммунальные'), findsWidgets);
      await scrollThrough(tester, 'История');
    });

    testWidgets('«Аналитика», четыре раздела, $percent', (tester) async {
      await pumpExtremeApp(tester, scale);
      await openExtremeTab(tester, 'Аналитика');
      for (final section in [
        'Категории',
        'Динамика',
        'Сравнение',
        'Операции',
      ]) {
        final tab = find.widgetWithText(Tab, section);
        await tester.ensureVisible(tab);
        await tester.tap(tab);
        await settleDatabase(tester);
        if (section == 'Операции') {
          expect(find.textContaining(_maxRub), findsWidgets);
        }
        await scrollThrough(tester, 'Аналитика → $section');
      }
    });
  }
}
