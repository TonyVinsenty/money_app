import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/format/period_label.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  group('formatPeriodLabel', () {
    test('день: «4 октября 2026»', () {
      final label = formatPeriodLabel(
        PeriodKind.day,
        dayRange(DateOnly(2026, 10, 4)),
      );

      expect(label, '4 октября 2026');
    });

    test(
      'неделя: даты через короткое тире (\\u2013), без года внутри года',
      () {
        final label = formatPeriodLabel(
          PeriodKind.week,
          weekRange(DateOnly(2026, 10, 4)),
        );

        expect(label, 'неделя 28.09\u201304.10');
      },
    );

    test('неделя через Новый год показывает годы у обеих дат', () {
      final label = formatPeriodLabel(
        PeriodKind.week,
        weekRange(DateOnly(2026, 1, 1)),
      );

      expect(label, 'неделя 29.12.2025\u201304.01.2026');
    });

    test('месяц: «октябрь 2026» со строчной буквы', () {
      final label = formatPeriodLabel(
        PeriodKind.month,
        monthRange(DateOnly(2026, 10, 15)),
      );

      expect(label, 'октябрь 2026');
    });

    test('год: «2026 год»', () {
      final label = formatPeriodLabel(
        PeriodKind.year,
        yearRange(DateOnly(2026, 5, 1)),
      );

      expect(label, '2026 год');
    });

    test('свой интервал: «с 01.09.2026 по 04.10.2026»', () {
      final label = formatPeriodLabel(
        PeriodKind.custom,
        DateRange(DateOnly(2026, 9, 1), DateOnly(2026, 10, 4)),
      );

      expect(label, 'с 01.09.2026 по 04.10.2026');
    });
  });
}
