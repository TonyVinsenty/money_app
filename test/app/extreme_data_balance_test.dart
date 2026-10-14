import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/features/accounts/presentation/accounts_section.dart';
import 'package:money_app/features/recurring/presentation/recurring_section.dart';
import 'package:money_app/features/settings/presentation/settings_screen.dart'
    show categoriesItemLabel;

import '../support/extreme_app.dart';
import '../support/extreme_data.dart';
import '../support/fixed_clock.dart';
import '../support/nbsp.dart';
import '../support/settle_database.dart';

/// Шаг 7.44 (К2): «Баланс», экран счёта, перевод, список и форма платежа,
/// «Настройки» и «Категории» (30 категорий) на наборе крайних данных,
/// 360 dp, шрифт 100 и 200 %; «следующий» для платежей 31-го и 29 февраля.
/// Прокручивает текущий экран, пока [target] не появится (ленивые списки
/// строят строки только у края экрана).
Future<void> _reveal(WidgetTester tester, Finder target) async {
  final vertical = find.byWidgetPredicate(
    (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
  );
  var dy = -200.0;
  for (var i = 0; i < 120; i++) {
    if (target.evaluate().isNotEmpty) {
      await tester.ensureVisible(target.first);
      await tester.pumpAndSettle();
      // Список мог уточнить длину и откатиться: проверяем после остановки.
      if (target.evaluate().isNotEmpty) return;
    }
    final position = tester.state<ScrollableState>(vertical.first).position;
    final before = position.pixels;
    await tester.drag(vertical.first, Offset(0, dy));
    await tester.pumpAndSettle();
    if (position.pixels == before) dy = -dy; // упёрлись в край — обратно
  }
  fail('Не нашли на экране: $target');
}

Future<void> _open(WidgetTester tester, Finder target) async {
  await _reveal(tester, target);
  await tester.pumpAndSettle();
  await tester.tap(target.first);
  await settleDatabase(tester);
}

/// Закрывает верхний экран корневого навигатора.
Future<void> _back(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator).first).pop();
  await settleDatabase(tester);
}

Finder _nextOf(String id, String text) => find.descendant(
  of: find.byKey(RecurringSection.rowKey(id)),
  matching: find.textContaining(text),
);

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

    testWidgets('«Баланс», счёт и перевод, $percent', (tester) async {
      await pumpExtremeApp(tester, scale);
      await openExtremeTab(tester, 'Баланс');
      expect(find.text(extremeAccountName(1)), findsWidgets);
      await scrollThrough(tester, 'Баланс');

      for (final i in [0, 1, 5]) {
        await _open(tester, find.text(extremeAccountName(i)));
        await scrollThrough(tester, 'Счёт $i');
        await _back(tester);
      }

      await _open(tester, find.byKey(AccountsSection.transferKey));
      await scrollThrough(tester, 'Перевод');
      await _back(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('платежи: список и форма, $percent', (tester) async {
      await pumpExtremeApp(tester, scale);
      await openExtremeTab(tester, 'Баланс');
      for (final id in ['p31', 'p29', 'pToday']) {
        await _open(tester, find.byKey(RecurringSection.rowKey(id)));
        expect(find.text(extremePaymentTitle(id)), findsWidgets);
        await scrollThrough(tester, 'Платёж $id');
        await _back(tester);
      }
      await _open(tester, find.byKey(RecurringSection.addButtonKey));
      await scrollThrough(tester, 'Новый платёж');
      await _back(tester);
    });

    testWidgets('«Настройки» и «Категории», $percent', (tester) async {
      await pumpExtremeApp(tester, scale);
      await openExtremeTab(tester, 'Настройки');
      await scrollThrough(tester, 'Настройки');
      await _open(tester, find.text(categoriesItemLabel));
      await _reveal(tester, find.text(extremeUnbreakable));
      await scrollThrough(tester, 'Категории');
    });
  }

  group('«следующий» на краях месяца', () {
    testWidgets('сегодня 12 октября: 31-го — 31 октября, 29 февраля — 28-го', (
      tester,
    ) async {
      await pumpExtremeApp(tester, 1);
      await openExtremeTab(tester, 'Баланс');
      await _reveal(tester, find.byKey(RecurringSection.rowKey('p29')));
      await tester.pumpAndSettle();
      expect(_nextOf('p31', 'следующий 31$dateNbspоктября'), findsOneWidget);
      // 2027 год невисокосный.
      expect(_nextOf('p29', 'следующий 28$dateNbspфевраля'), findsOneWidget);
    });

    testWidgets('февраль 2027: оба — 28 февраля', (tester) async {
      await pumpExtremeApp(
        tester,
        1,
        clock: FixedClock(DateTime(2027, 2, 10, 12)),
      );
      await openExtremeTab(tester, 'Баланс');
      await _reveal(tester, find.byKey(RecurringSection.rowKey('p29')));
      await tester.pumpAndSettle();
      expect(_nextOf('p31', 'следующий 28$dateNbspфевраля'), findsOneWidget);
      expect(_nextOf('p29', 'следующий 28$dateNbspфевраля'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
