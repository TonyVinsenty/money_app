import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/format/day_label.dart';
import 'package:money_app/core/time/date_only.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  final today = DateOnly(2026, 9, 20);

  test('сегодня и вчера — словами', () {
    expect(dayLabel(today, today: today), 'Сегодня');
    expect(dayLabel(DateOnly(2026, 9, 19), today: today), 'Вчера');
  });

  test('вчера через границу месяца и года', () {
    expect(
      dayLabel(DateOnly(2026, 8, 31), today: DateOnly(2026, 9, 1)),
      'Вчера',
    );
    expect(
      dayLabel(DateOnly(2025, 12, 31), today: DateOnly(2026, 1, 1)),
      'Вчера',
    );
  });

  test('остальные дни — датой по-русски', () {
    expect(
      dayLabel(DateOnly(2026, 9, 18), today: today),
      contains('18 сентября 2026'),
    );
  });

  group('historyDayLabel', () {
    test('сегодня и вчера — словами', () {
      expect(historyDayLabel(today, today: today), 'Сегодня');
      expect(historyDayLabel(DateOnly(2026, 9, 19), today: today), 'Вчера');
    });

    test('вчера через границу года — словом, не датой', () {
      expect(
        historyDayLabel(DateOnly(2025, 12, 31), today: DateOnly(2026, 1, 1)),
        'Вчера',
      );
    });

    test('текущий год — день недели, число и месяц без года', () {
      expect(
        historyDayLabel(DateOnly(2026, 9, 18), today: today),
        'пятница, 18 сентября',
      );
      expect(
        historyDayLabel(DateOnly(2026, 1, 1), today: today),
        'четверг, 1 января',
      );
    });

    test('прошлый год — с годом', () {
      final label = historyDayLabel(DateOnly(2025, 9, 19), today: today);
      expect(label, startsWith('пятница, 19 сентября 2025'));
      expect(label, endsWith('г.'));
    });

    test('31 декабря прошлого года при сегодня 2 января — с годом', () {
      expect(
        historyDayLabel(DateOnly(2025, 12, 31), today: DateOnly(2026, 1, 2)),
        contains('31 декабря 2025'),
      );
    });
  });
}
