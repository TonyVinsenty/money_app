import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/format/day_label.dart';
import 'package:money_app/core/time/date_only.dart';

/// Неразрывный пробел (U+00A0) между числом и месяцем.
final String nbsp = String.fromCharCode(0x00A0);

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

  test('остальные дни текущего года — без года', () {
    expect(dayLabel(DateOnly(2026, 9, 18), today: today), '18$nbspсентября');
    expect(dayLabel(DateOnly(2026, 11, 9), today: today), '9$nbspноября');
  });

  test('день прошлого года — с годом', () {
    final label = dayLabel(DateOnly(2025, 9, 18), today: today);
    expect(label, startsWith('18$nbspсентября 2025'));
    expect(label, endsWith('г.'));
  });

  test('«Сегодня» и «Вчера» не тронуты: без неразрывного пробела', () {
    expect(dayLabel(today, today: today), 'Сегодня');
    expect(dayLabel(DateOnly(2026, 9, 19), today: today), 'Вчера');
    expect(historyDayLabel(today, today: today), 'Сегодня');
    expect(historyDayLabel(DateOnly(2026, 9, 19), today: today), 'Вчера');
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
        'Пятница, 18$nbspсентября',
      );
      expect(
        historyDayLabel(DateOnly(2026, 1, 1), today: today),
        'Четверг, 1$nbspянваря',
      );
    });

    test('прошлый год — с годом', () {
      final label = historyDayLabel(DateOnly(2025, 9, 19), today: today);
      expect(label, startsWith('Пятница, 19$nbspсентября 2025'));
      expect(label, endsWith('г.'));
    });

    test('первая буква заглавная', () {
      final label = historyDayLabel(DateOnly(2026, 9, 18), today: today);
      expect(label[0], label[0].toUpperCase());
      expect(label[0], 'П');
    });

    test('31 декабря прошлого года при сегодня 2 января — с годом', () {
      expect(
        historyDayLabel(DateOnly(2025, 12, 31), today: DateOnly(2026, 1, 2)),
        contains('31$nbspдекабря 2025'),
      );
    });
  });
}
