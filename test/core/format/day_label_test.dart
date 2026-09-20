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
}
