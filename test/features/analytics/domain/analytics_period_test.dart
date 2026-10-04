import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';

/// Фиксированный «сегодня» для всех тестов: воскресенье, 4 октября 2026.
final _today = DateOnly(2026, 10, 4);

DateRange _range(DateOnly start, DateOnly end) => DateRange(start, end);

void main() {
  group('currentPeriod', () {
    test('неделя всегда начинается с понедельника: воскресенье 04.10.2026 '
        'относится к неделе 28.09-04.10', () {
      final period = currentPeriod(PeriodKind.week, _today);

      expect(
        period.range,
        _range(DateOnly(2026, 9, 28), DateOnly(2026, 10, 4)),
      );
    });

    test('понедельник 05.10.2026 — первый день новой недели 05.10-11.10', () {
      final period = currentPeriod(PeriodKind.week, DateOnly(2026, 10, 5));

      expect(
        period.range,
        _range(DateOnly(2026, 10, 5), DateOnly(2026, 10, 11)),
      );
    });

    test(
      'неделя через Новый год: 01.01.2026 входит в 29.12.2025-04.01.2026',
      () {
        final period = currentPeriod(PeriodKind.week, DateOnly(2026, 1, 1));

        expect(
          period.range,
          _range(DateOnly(2025, 12, 29), DateOnly(2026, 1, 4)),
        );
      },
    );

    test('день — один и тот же день', () {
      final period = currentPeriod(PeriodKind.day, DateOnly(2026, 9, 15));

      expect(
        period,
        AnalyticsPeriod(
          PeriodKind.day,
          _range(DateOnly(2026, 9, 15), DateOnly(2026, 9, 15)),
        ),
      );
    });

    test('месяц — от первого до последнего дня', () {
      final period = currentPeriod(PeriodKind.month, _today);

      expect(
        period.range,
        _range(DateOnly(2026, 10, 1), DateOnly(2026, 10, 31)),
      );
    });

    test('год — с 1 января по 31 декабря', () {
      final period = currentPeriod(PeriodKind.year, _today);

      expect(
        period.range,
        _range(DateOnly(2026, 1, 1), DateOnly(2026, 12, 31)),
      );
    });

    test('свой интервал не имеет «текущего» периода: ArgumentError', () {
      expect(
        () => currentPeriod(PeriodKind.custom, _today),
        throwsArgumentError,
      );
    });
  });

  group('previousPeriod', () {
    test('назад из января 2026 — декабрь 2025 целиком', () {
      final january = currentPeriod(PeriodKind.month, DateOnly(2026, 1, 15));

      expect(
        previousPeriod(january)!.range,
        _range(DateOnly(2025, 12, 1), DateOnly(2025, 12, 31)),
      );
    });

    test('назад из недели 05.10-11.10 — неделя 28.09-04.10', () {
      final week = currentPeriod(PeriodKind.week, DateOnly(2026, 10, 7));

      expect(
        previousPeriod(week)!.range,
        _range(DateOnly(2026, 9, 28), DateOnly(2026, 10, 4)),
      );
    });

    test('назад из недели 29.12-04.01 — неделя 22.12-28.12', () {
      final week = currentPeriod(PeriodKind.week, DateOnly(2026, 1, 2));

      expect(
        previousPeriod(week)!.range,
        _range(DateOnly(2025, 12, 22), DateOnly(2025, 12, 28)),
      );
    });

    test('назад из марта 2028 — февраль високосного года, 29 дней', () {
      final march = currentPeriod(PeriodKind.month, DateOnly(2028, 3, 10));
      final february = previousPeriod(march)!;

      expect(
        february.range,
        _range(DateOnly(2028, 2, 1), DateOnly(2028, 2, 29)),
      );
      expect(february.range.lengthInDays, 29);
    });

    test('назад из марта 2027 — февраль обычного года, 28 дней', () {
      final march = currentPeriod(PeriodKind.month, DateOnly(2027, 3, 10));

      expect(previousPeriod(march)!.range.lengthInDays, 28);
    });

    test('назад для дня — предыдущий день', () {
      final day = currentPeriod(PeriodKind.day, DateOnly(2026, 3, 1));

      expect(
        previousPeriod(day)!.range,
        _range(DateOnly(2026, 2, 28), DateOnly(2026, 2, 28)),
      );
    });

    test('назад для года — прошлый год', () {
      final year = currentPeriod(PeriodKind.year, _today);

      expect(
        previousPeriod(year)!.range,
        _range(DateOnly(2025, 1, 1), DateOnly(2025, 12, 31)),
      );
    });

    test('свой интервал не сдвигается: null', () {
      final custom = customPeriod(
        DateOnly(2026, 9, 1),
        DateOnly(2026, 9, 10),
        today: _today,
      );

      expect(previousPeriod(custom), isNull);
    });
  });

  group('nextPeriod и canGoForward', () {
    test('вперёд из текущего месяца нельзя: null', () {
      final october = currentPeriod(PeriodKind.month, _today);

      expect(nextPeriod(october, _today), isNull);
      expect(canGoForward(october, _today), isFalse);
    });

    test(
      'вперёд из текущей недели нельзя, даже если в ней есть будущие дни',
      () {
        // Неделя 28.09-04.10 содержит сегодня; следующая 05.10 — в будущем.
        final week = currentPeriod(PeriodKind.week, _today);

        expect(nextPeriod(week, _today), isNull);
      },
    );

    test('вперёд из прошлого месяца — текущий месяц', () {
      final september = currentPeriod(PeriodKind.month, DateOnly(2026, 9, 1));

      expect(
        nextPeriod(september, _today)!.range,
        _range(DateOnly(2026, 10, 1), DateOnly(2026, 10, 31)),
      );
      expect(canGoForward(september, _today), isTrue);
    });

    test('вперёд из прошлой недели 21.09-27.09 — неделя 28.09-04.10', () {
      final week = currentPeriod(PeriodKind.week, DateOnly(2026, 9, 22));

      expect(
        nextPeriod(week, _today)!.range,
        _range(DateOnly(2026, 9, 28), DateOnly(2026, 10, 4)),
      );
    });

    test('вперёд из декабря 2025 — январь 2026, когда сегодня в январе', () {
      final december = currentPeriod(PeriodKind.month, DateOnly(2025, 12, 5));
      final january = DateOnly(2026, 1, 20);

      expect(
        nextPeriod(december, january)!.range,
        _range(DateOnly(2026, 1, 1), DateOnly(2026, 1, 31)),
      );
    });

    test('свой интервал не сдвигается: null', () {
      final custom = customPeriod(
        DateOnly(2026, 9, 1),
        DateOnly(2026, 9, 10),
        today: _today,
      );

      expect(nextPeriod(custom, _today), isNull);
      expect(canGoForward(custom, _today), isFalse);
    });
  });

  group('customPeriod', () {
    test('интервал с границами сохраняется как есть', () {
      final custom = customPeriod(
        DateOnly(2026, 9, 3),
        DateOnly(2026, 9, 17),
        today: _today,
      );

      expect(custom.kind, PeriodKind.custom);
      expect(custom.range, _range(DateOnly(2026, 9, 3), DateOnly(2026, 9, 17)));
    });

    test('один день — допустимый интервал', () {
      final custom = customPeriod(
        DateOnly(2026, 9, 3),
        DateOnly(2026, 9, 3),
        today: _today,
      );

      expect(custom.range.lengthInDays, 1);
    });

    test('начало позже конца — ArgumentError', () {
      expect(
        () => customPeriod(
          DateOnly(2026, 9, 17),
          DateOnly(2026, 9, 3),
          today: _today,
        ),
        throwsArgumentError,
      );
    });

    test('конец в будущем — ArgumentError', () {
      expect(
        () => customPeriod(
          DateOnly(2026, 10, 1),
          DateOnly(2026, 10, 5),
          today: _today,
        ),
        throwsArgumentError,
      );
    });

    test('конец сегодня — допустим', () {
      expect(
        () => customPeriod(DateOnly(2026, 10, 1), _today, today: _today),
        returnsNormally,
      );
    });
  });

  group('switchKind', () {
    test('неделя 28.09-04.10 при сегодня 04.10 → октябрь', () {
      final week = currentPeriod(PeriodKind.week, _today);

      final month = switchKind(week, PeriodKind.month, _today);

      expect(
        month.range,
        _range(DateOnly(2026, 10, 1), DateOnly(2026, 10, 31)),
      );
    });

    test('неделя 21.09-27.09 → сентябрь', () {
      final week = currentPeriod(PeriodKind.week, DateOnly(2026, 9, 22));

      final month = switchKind(week, PeriodKind.month, _today);

      expect(month.range, _range(DateOnly(2026, 9, 1), DateOnly(2026, 9, 30)));
    });

    test('день 15.09 → неделя 14.09-20.09', () {
      final day = currentPeriod(PeriodKind.day, DateOnly(2026, 9, 15));

      final week = switchKind(day, PeriodKind.week, _today);

      expect(week.range, _range(DateOnly(2026, 9, 14), DateOnly(2026, 9, 20)));
    });

    test('опорный день не уходит в будущее: месяц, который продолжается, '
        'берётся по сегодняшнему дню', () {
      // Свой интервал 01.10-04.10 (конец сегодня): опорный день — 04.10.
      final custom = customPeriod(DateOnly(2026, 10, 1), _today, today: _today);

      final month = switchKind(custom, PeriodKind.month, _today);

      expect(
        month.range,
        _range(DateOnly(2026, 10, 1), DateOnly(2026, 10, 31)),
      );
    });

    test('переход на свой интервал — ArgumentError', () {
      final week = currentPeriod(PeriodKind.week, _today);

      expect(
        () => switchKind(week, PeriodKind.custom, _today),
        throwsArgumentError,
      );
    });
  });
}
