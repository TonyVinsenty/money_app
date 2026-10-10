import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/domain/comparison.dart';

DateRange _r(int y1, int m1, int d1, int y2, int m2, int d2) =>
    DateRange(DateOnly(y1, m1, d1), DateOnly(y2, m2, d2));

void main() {
  final today = DateOnly(2026, 10, 11); // воскресенье

  group('comparisonRange', () {
    test('текущий месяц, 11 октября -> 1-11 сентября', () {
      final p = currentPeriod(PeriodKind.month, today);
      expect(comparisonRange(p, today), _r(2026, 9, 1, 2026, 9, 11));
    });

    test('31 октября (текущий) -> 1-30 сентября', () {
      final t = DateOnly(2026, 10, 31);
      final p = currentPeriod(PeriodKind.month, t);
      expect(comparisonRange(p, t), _r(2026, 9, 1, 2026, 9, 30));
    });

    test('високосный февраль как прошлый месяц', () {
      final t = DateOnly(2028, 3, 1);
      expect(
        comparisonRange(currentPeriod(PeriodKind.month, t), t),
        _r(2028, 2, 1, 2028, 2, 1),
      );
      final t2 = DateOnly(2028, 3, 31);
      expect(
        comparisonRange(currentPeriod(PeriodKind.month, t2), t2),
        _r(2028, 2, 1, 2028, 2, 29),
      );
    });

    test('прошедший сентябрь -> весь август', () {
      final p = currentPeriod(PeriodKind.month, DateOnly(2026, 9, 15));
      expect(comparisonRange(p, today), _r(2026, 8, 1, 2026, 8, 31));
    });

    test('январь -> декабрь прошлого года', () {
      final p = currentPeriod(PeriodKind.month, DateOnly(2026, 1, 20));
      expect(comparisonRange(p, today), _r(2025, 12, 1, 2025, 12, 31));
    });

    test('текущий год -> та же дата прошлого года', () {
      final p = currentPeriod(PeriodKind.year, today);
      expect(comparisonRange(p, today), _r(2025, 1, 1, 2025, 10, 11));
    });

    test('текущий год с 29 февраля -> 28 февраля', () {
      final t = DateOnly(2028, 2, 29);
      expect(
        comparisonRange(currentPeriod(PeriodKind.year, t), t),
        _r(2027, 1, 1, 2027, 2, 28),
      );
    });

    test('прошедший год -> весь предыдущий', () {
      final p = currentPeriod(PeriodKind.year, DateOnly(2025, 6, 1));
      expect(comparisonRange(p, today), _r(2024, 1, 1, 2024, 12, 31));
    });

    test('неделя Пн-Сб -> Пн-Сб прошлой недели', () {
      final t = DateOnly(2026, 10, 10); // суббота
      final p = currentPeriod(PeriodKind.week, t);
      expect(p.range.start, DateOnly(2026, 10, 5));
      expect(comparisonRange(p, t), _r(2026, 9, 28, 2026, 10, 3));
    });

    test('прошедшая неделя -> целая прошлая', () {
      final p = currentPeriod(PeriodKind.week, DateOnly(2026, 10, 1));
      expect(comparisonRange(p, today), _r(2026, 9, 21, 2026, 9, 27));
    });

    test('свой интервал 10 дней -> 10 дней перед ним', () {
      final p = customPeriod(
        DateOnly(2026, 10, 2),
        DateOnly(2026, 10, 11),
        today: today,
      );
      expect(comparisonRange(p, today), _r(2026, 9, 22, 2026, 10, 1));
    });

    test('сегодня -> вчера; прошедший день -> предыдущий', () {
      expect(
        comparisonRange(currentPeriod(PeriodKind.day, today), today),
        _r(2026, 10, 10, 2026, 10, 10),
      );
      expect(
        comparisonRange(
          currentPeriod(PeriodKind.day, DateOnly(2026, 10, 1)),
          today,
        ),
        _r(2026, 9, 30, 2026, 9, 30),
      );
    });
  });

  group('dataWindow', () {
    test('от начала сравнения до конца периода', () {
      final p = currentPeriod(PeriodKind.month, today);
      expect(dataWindow(p, today), _r(2026, 9, 1, 2026, 10, 31));
    });

    test('свой интервал', () {
      final p = customPeriod(
        DateOnly(2026, 10, 2),
        DateOnly(2026, 10, 11),
        today: today,
      );
      expect(dataWindow(p, today), _r(2026, 9, 22, 2026, 10, 11));
    });
  });
}
