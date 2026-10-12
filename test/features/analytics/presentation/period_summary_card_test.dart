import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/ui/amount_switcher.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/analytics/domain/period_summary.dart';
import 'package:money_app/features/analytics/presentation/period_summary_card.dart';

PeriodSummary _summary(int expenseMinor) => PeriodSummary(
  income: Money.fromMinor(500000, 'RUB'),
  expense: Money.fromMinor(expenseMinor, 'RUB'),
  incomeCount: 1,
  expenseCount: 2,
);

Widget _app(PeriodSummary summary, {bool reduceMotion = false}) => MaterialApp(
  theme: AppTheme.light(),
  home: MediaQuery(
    data: MediaQueryData(
      size: const Size(360, 640),
      disableAnimations: reduceMotion,
    ),
    child: Scaffold(body: PeriodSummaryCard(summary: summary)),
  ),
);

Finder _in(Key key, String text) =>
    find.descendant(of: find.byKey(key), matching: find.text(text));

void main() {
  final before = '−${formatMoney(Money.fromMinor(100000, 'RUB'))}';
  final after = '−${formatMoney(Money.fromMinor(250000, 'RUB'))}';
  final income = '+${formatMoney(Money.fromMinor(500000, 'RUB'))}';

  testWidgets('другой период: расходы сменяются плавно, доходы на месте', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_summary(100000)));
    await tester.pumpWidget(_app(_summary(250000)));
    await tester.pump(amountSwitchDuration ~/ 2);

    expect(_in(PeriodSummaryCard.expenseKey, before), findsOneWidget);
    expect(_in(PeriodSummaryCard.expenseKey, after), findsOneWidget);
    expect(_in(PeriodSummaryCard.incomeKey, income), findsOneWidget);

    await tester.pumpAndSettle();
    expect(_in(PeriodSummaryCard.expenseKey, before), findsNothing);
    expect(_in(PeriodSummaryCard.expenseKey, after), findsOneWidget);
  });

  testWidgets('«Уменьшить движение»: сразу новая сумма', (tester) async {
    await tester.pumpWidget(_app(_summary(100000), reduceMotion: true));
    await tester.pumpWidget(_app(_summary(250000), reduceMotion: true));

    expect(_in(PeriodSummaryCard.expenseKey, before), findsNothing);
    expect(_in(PeriodSummaryCard.expenseKey, after), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
