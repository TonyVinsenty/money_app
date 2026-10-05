import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/format/period_label.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  final today = DateOnly(2026, 10, 4);

  String label(PeriodKind kind, DateRange range) =>
      formatPeriodLabel(kind, range, today: today);

  String week(DateOnly day) => label(PeriodKind.week, weekRange(day));

  String custom(DateOnly a, DateOnly b) =>
      label(PeriodKind.custom, DateRange(a, b));

  group('formatPeriodLabel: день', () {
    String day(DateOnly d) => label(PeriodKind.day, dayRange(d));

    test('сегодня', () => expect(day(DateOnly(2026, 10, 4)), 'Сегодня'));
    test('вчера', () => expect(day(DateOnly(2026, 10, 3)), 'Вчера'));
    test(
      'другой день этого года: день недели с заглавной',
      () => expect(day(DateOnly(2026, 10, 2)), 'Пятница, 2 октября'),
    );
    test(
      'не этот год: без дня недели, с годом',
      () => expect(day(DateOnly(2025, 10, 2)), '2 октября 2025'),
    );
    test('вчера через Новый год: 31 декабря прошлого года с годом', () {
      final label = formatPeriodLabel(
        PeriodKind.day,
        dayRange(DateOnly(2025, 12, 31)),
        today: DateOnly(2026, 1, 1),
      );
      expect(label, '31 декабря 2025');
    });
  });

  group('formatPeriodLabel: неделя', () {
    test('в одном месяце', () {
      expect(week(DateOnly(2026, 10, 7)), '5\u201311 октября');
    });
    test('через месяц', () {
      expect(week(DateOnly(2026, 10, 4)), '28 сентября \u2013 4 октября');
    });
    test('через Новый год', () {
      expect(
        week(DateOnly(2026, 1, 1)),
        '29 декабря 2025 \u2013 4 января 2026',
      );
    });
    test('прошлый год, один месяц: год в конце', () {
      expect(week(DateOnly(2025, 11, 26)), '24\u201330 ноября 2025');
    });
    test('прошлый год, два месяца: год в конце', () {
      expect(week(DateOnly(2025, 10, 30)), '27 октября \u2013 2 ноября 2025');
    });
  });

  group('formatPeriodLabel: месяц и год', () {
    test('месяц', () {
      expect(
        label(PeriodKind.month, monthRange(DateOnly(2026, 10, 15))),
        'Октябрь 2026',
      );
    });
    test('год', () {
      expect(label(PeriodKind.year, yearRange(DateOnly(2026, 5, 1))), '2026');
    });
  });

  group('formatPeriodLabel: свой интервал', () {
    test('внутри месяца', () {
      expect(
        custom(DateOnly(2026, 9, 1), DateOnly(2026, 9, 15)),
        '1\u201315 сентября 2026',
      );
    });
    test('через месяц', () {
      expect(
        custom(DateOnly(2026, 9, 28), DateOnly(2026, 10, 4)),
        '28 сентября \u2013 4 октября 2026',
      );
    });
    test('через год', () {
      expect(
        custom(DateOnly(2025, 12, 29), DateOnly(2026, 1, 4)),
        '29 декабря 2025 \u2013 4 января 2026',
      );
    });
    test('один день', () {
      expect(
        custom(DateOnly(2026, 9, 15), DateOnly(2026, 9, 15)),
        '15 сентября 2026',
      );
    });
  });
}
