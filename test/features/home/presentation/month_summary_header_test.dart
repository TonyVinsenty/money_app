import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/period_switcher.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/home/presentation/month_summary_card.dart';

import '../../../support/roboto_font.dart';

Future<void> _pump(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: MonthSummaryCard(
            expenses: Stream.value(Money.zero('RUB')),
            income: Stream.value(Money.zero('RUB')),
            month: DateOnly(2026, 10, 4),
            onPreviousMonth: () {},
            onNextMonth: () {},
            onHideAmountsChanged: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    await loadRoboto();
  });

  double fontSize(WidgetTester tester) =>
      tester.widget<Text>(find.text('Октябрь 2026')).style!.fontSize!;

  testWidgets('320 dp: подпись не ужата, кнопки 48 dp, всё помещается', (
    tester,
  ) async {
    await _pump(tester, 320);
    expect(fontSize(tester), 14.0);
    // Нет FittedBox, который ужимал бы подпись.
    expect(
      find.descendant(
        of: find.byType(PeriodSwitcher),
        matching: find.byType(FittedBox),
      ),
      findsNothing,
    );
    for (final key in [
      PeriodSwitcher.previousKey,
      PeriodSwitcher.nextKey,
      MonthSummaryCard.hideAmountsKey,
    ]) {
      final size = tester.getSize(find.byKey(key));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    // Пустого места слева нет: стрелка «назад» у левого края содержимого.
    final card = tester.getRect(find.byType(MonthSummaryCard));
    expect(
      tester.getTopLeft(find.byKey(PeriodSwitcher.previousKey)).dx,
      lessThanOrEqualTo(card.left + 16),
    );
    final eye = tester.getRect(find.byKey(MonthSummaryCard.hideAmountsKey));
    expect(eye.right, lessThanOrEqualTo(card.right));
    // Значок «назад» стоит по линии текста колонок, а подписи досталось
    // +24 dp: шапка шире содержимого карточки (256 dp) на 2 * 12 (минус «глаз» 48).
    final iconLeft = tester.getTopLeft(
      find.descendant(
        of: find.byKey(PeriodSwitcher.previousKey),
        matching: find.byType(Icon),
      ),
    );
    expect(iconLeft.dx, closeTo(tester.getTopLeft(find.text('Расходы')).dx, 1));
    expect(tester.getSize(find.byType(PeriodSwitcher)).width, 256 + 24 - 48);
    expect(tester.takeException(), isNull);
  });

  testWidgets('412 dp: вид прежний, подпись по центру карточки', (
    tester,
  ) async {
    await _pump(tester, 412);
    expect(fontSize(tester), 14.0);
    final card = tester.getRect(find.byType(MonthSummaryCard));
    final label = tester.getRect(find.text('Октябрь 2026'));
    expect(label.center.dx, closeTo(card.center.dx, 1));
    final previous = tester.getRect(find.byKey(PeriodSwitcher.previousKey));
    // Слева прежний пустой блок 48 dp: стрелка не у самого края.
    expect(previous.left, card.left + 16 - 12 + 48);
    expect(tester.takeException(), isNull);
  });
}
