import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/domain/buckets.dart';
import 'package:money_app/features/analytics/presentation/analytics_texts.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

final _today = DateOnly(2026, 10, 11);

Map<int, String> _labels(AnalyticsPeriod p) => dynamicsAxisLabels(
  p,
  bucketTotals(const [], p, type: TransactionType.expense, currency: 'RUB'),
);

AnalyticsPeriod _custom(DateOnly start, DateOnly end) =>
    customPeriod(start, end, today: end);

void main() {
  test('месяц: 1, 10, 20 и последний день', () {
    expect(_labels(currentPeriod(PeriodKind.month, _today)), {
      0: '1',
      9: '10',
      19: '20',
      30: '31',
    });
    expect(_labels(currentPeriod(PeriodKind.month, DateOnly(2026, 2, 5))), {
      0: '1',
      9: '10',
      19: '20',
      27: '28',
    });
  });

  test('неделя: все семь дней, Пн-Вс', () {
    expect(_labels(currentPeriod(PeriodKind.week, _today)), {
      0: 'Пн',
      1: 'Вт',
      2: 'Ср',
      3: 'Чт',
      4: 'Пт',
      5: 'Сб',
      6: 'Вс',
    });
  });

  test('год: первые буквы всех 12 месяцев', () {
    final l = _labels(currentPeriod(PeriodKind.year, _today));
    expect(l.length, 12);
    expect(l.values.join(' '), 'Я Ф М А М И И А С О Н Д');
  });

  test('день: подписей нет', () {
    expect(_labels(currentPeriod(PeriodKind.day, _today)), isEmpty);
  });

  test('свой по дням: первый, средний и последний как «15.12»', () {
    expect(_labels(_custom(DateOnly(2026, 12, 15), DateOnly(2027, 1, 14))), {
      0: '15.12',
      15: '30.12',
      30: '14.01',
    });
  });

  test('свой по дням, очень короткий: без повторов', () {
    expect(_labels(_custom(DateOnly(2026, 10, 5), DateOnly(2026, 10, 5))), {
      0: '05.10',
    });
    expect(_labels(_custom(DateOnly(2026, 10, 5), DateOnly(2026, 10, 6))), {
      0: '05.10',
      1: '06.10',
    });
  });

  test(
    'свой по месяцам: до 12 - все, до 24 - каждый второй, дальше - третий',
    () {
      final p10 = _labels(
        _custom(DateOnly(2026, 1, 1), DateOnly(2026, 10, 31)),
      );
      expect(p10.length, 10);
      final p18 = _labels(_custom(DateOnly(2025, 1, 1), DateOnly(2026, 6, 30)));
      expect(p18.keys, [for (var i = 0; i < 18; i += 2) i]);
      final p36 = _labels(
        _custom(DateOnly(2024, 1, 1), DateOnly(2026, 12, 31)),
      );
      expect(p36.keys, [for (var i = 0; i < 36; i += 3) i]);
      expect(p36[0], 'Я');
      expect(p36[3], 'А');
    },
  );
}
