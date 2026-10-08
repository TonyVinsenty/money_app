import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/other_currencies_hint.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/presentation/analytics_screen.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/presentation/history/history_screen.dart';

/// Подсказка «Здесь только операции в основной валюте» (шаг 5.10q).
final _today = DateOnly(2026, 9, 20);
const _text =
    'Здесь только операции в основной валюте (\$). Остальные появятся снова, '
    'если вернуть их валюту в «Настройках».';

Widget _history({Stream<bool>? other}) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(
    body: HistoryScreen(
      transactions: Stream.value(<Transaction>[]),
      categories: Stream.value(const <Category>[]),
      today: _today,
      month: _today,
      hasAnyTransactions: true,
      onTransactionTap: (_) {},
      hasOtherCurrencies: other,
      currencySymbol: '\$',
    ),
  ),
);

Widget _analytics({Stream<bool>? other}) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(
    body: AnalyticsScreen(
      period: currentPeriod(PeriodKind.month, _today),
      today: _today,
      onKindSelected: (_) {},
      onPrevious: null,
      onNext: null,
      transactions: Stream.value((
        range: currentPeriod(PeriodKind.month, _today).range,
        transactions: <Transaction>[],
      )),
      categories: Stream.value(const <Category>[]),
      hasOtherCurrencies: other,
      currencySymbol: '\$',
    ),
  ),
);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  test('текст подсказки подставляет знак валюты', () {
    expect(otherCurrenciesHintText('\$'), _text);
  });

  for (final (name, build)
      in <(String, Widget Function({Stream<bool>? other}))>[
        ('«История»', _history),
        ('«Аналитика»', _analytics),
      ]) {
    testWidgets('$name: подсказка есть при операциях в других валютах', (
      tester,
    ) async {
      await tester.pumpWidget(build(other: Stream.value(true)));
      await tester.pumpAndSettle();
      expect(find.text(_text), findsOneWidget);
    });

    testWidgets('$name: подсказки нет без таких операций и без потока', (
      tester,
    ) async {
      await tester.pumpWidget(build(other: Stream.value(false)));
      await tester.pumpAndSettle();
      expect(find.byKey(otherCurrenciesHintKey), findsNothing);

      await tester.pumpWidget(build());
      await tester.pumpAndSettle();
      expect(find.byKey(otherCurrenciesHintKey), findsNothing);
    });
  }
}
