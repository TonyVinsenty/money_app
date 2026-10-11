import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/masked_amount.dart';
import 'package:money_app/features/analytics/domain/buckets.dart';
import 'package:money_app/features/analytics/domain/period_comparison.dart';
import 'package:money_app/features/analytics/presentation/analytics_texts.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

final _today = DateOnly(2026, 10, 11);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  final money = Money.fromMinor(1234567, 'RUB');
  final change = AmountChange(
    current: money,
    previous: Money.fromMinor(800000, 'RUB'),
  );
  final noDigits = isNot(contains(RegExp(r'\d{3}')));

  test('по умолчанию суммы видны', () {
    expect(dynamicsAverageText(money, BucketStep.day), contains('345,67'));
    expect(comparisonRowTitle('Кафе', change), contains('345,67'));
  });

  test('сравнение', () {
    expect(
      comparisonTotalTitle(TransactionType.expense, money, hidden: true),
      'Расходы: $maskedMoneyText',
    );
    expect(
      comparisonTotalTitle(
        TransactionType.expense,
        money,
        spoken: true,
        hidden: true,
      ),
      'Расходы: $hiddenAmountLabel',
    );
    final summary = comparisonSummaryText(
      change,
      TransactionType.expense,
      'в сентябре',
      hidden: true,
    );
    expect(summary, contains(maskedMoneyText));
    expect(summary, noDigits);
    expect(
      comparisonRowTitle('Кафе', change, hidden: true),
      'Кафе · $maskedMoneyText',
    );
    expect(
      comparisonRowDelta(change, hidden: true),
      allOf(contains(maskedMoneyText), noDigits),
    );
    expect(
      comparisonRowSpoken('Кафе', change, hidden: true),
      allOf(contains(hiddenAmountLabel), noDigits),
    );
  });

  test('операции', () {
    expect(
      operationsStatSubtitle(3, money, hidden: true),
      '3 операции · средний чек $maskedMoneyText',
    );
    expect(
      operationsStatSpoken('Кафе', 3, money, hidden: true),
      contains(hiddenAmountLabel),
    );
  });

  test('динамика', () {
    expect(
      dynamicsAverageText(money, BucketStep.day, hidden: true),
      'В среднем $maskedMoneyText в день',
    );
    expect(
      dynamicsAverageText(money, BucketStep.day, spoken: true, hidden: true),
      'В среднем $hiddenAmountLabel в день',
    );
    expect(
      dynamicsForecastText(money, _today, hidden: true),
      endsWith('≈ $maskedMoneyText'),
    );
    expect(
      dynamicsForecastText(money, _today, spoken: true, hidden: true),
      endsWith('примерно $hiddenAmountLabel'),
    );
    final bucket = Bucket(range: DateRange(_today, _today), amount: money);
    expect(
      dynamicsSelectedText(bucket, BucketStep.day, _today, hidden: true),
      endsWith(': $maskedMoneyText'),
    );
    expect(
      dynamicsRowSpoken(bucket, BucketStep.day, _today, hidden: true),
      endsWith(', $hiddenAmountLabel'),
    );
  });
}
