import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/format/date_format.dart';
import 'package:money_app/core/time/date_only.dart';

/// Узкий неразрывный пробел (U+202F): intl ставит его перед «г.».
final String narrowNbsp = String.fromCharCode(0x202F);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  group('formatDate', () {
    test('19 сентября 2026', () {
      expect(formatDate(DateOnly(2026, 9, 19)), contains('19 сентября 2026'));
    });

    test('точная строка intl: год, узкий неразрывный пробел, «г.»', () {
      expect(
        formatDate(DateOnly(2026, 9, 19)),
        '19 сентября 2026$narrowNbspг.',
      );
    });

    test('1 января', () {
      expect(formatDate(DateOnly(2026, 1, 1)), contains('1 января 2026'));
    });

    test('29 февраля високосного года', () {
      expect(formatDate(DateOnly(2024, 2, 29)), contains('29 февраля 2024'));
    });

    test('31 декабря', () {
      expect(formatDate(DateOnly(2026, 12, 31)), contains('31 декабря 2026'));
    });

    test('все 12 месяцев в родительном падеже', () {
      const genitive = [
        'января',
        'февраля',
        'марта',
        'апреля',
        'мая',
        'июня',
        'июля',
        'августа',
        'сентября',
        'октября',
        'ноября',
        'декабря',
      ];
      for (var month = 1; month <= 12; month++) {
        expect(
          formatDate(DateOnly(2026, month, 1)),
          contains('1 ${genitive[month - 1]} 2026'),
          reason: 'месяц $month',
        );
      }
    });
  });

  group('formatMonthName', () {
    test('все 12 месяцев: именительный падеж, маленькая буква', () {
      const nominative = [
        'январь',
        'февраль',
        'март',
        'апрель',
        'май',
        'июнь',
        'июль',
        'август',
        'сентябрь',
        'октябрь',
        'ноябрь',
        'декабрь',
      ];
      for (var month = 1; month <= 12; month++) {
        expect(
          formatMonthName(DateOnly(2026, month, 15)),
          nominative[month - 1],
          reason: 'месяц $month',
        );
      }
    });
  });

  group('formatMonthYear', () {
    test('сентябрь 2026', () {
      expect(
        formatMonthYear(DateOnly(2026, 9, 19)),
        'сентябрь 2026$narrowNbspг.',
      );
    });

    test('день месяца не влияет на результат', () {
      expect(
        formatMonthYear(DateOnly(2026, 2, 1)),
        formatMonthYear(DateOnly(2026, 2, 28)),
      );
    });

    test('все 12 месяцев в именительном падеже', () {
      const nominative = [
        'январь',
        'февраль',
        'март',
        'апрель',
        'май',
        'июнь',
        'июль',
        'август',
        'сентябрь',
        'октябрь',
        'ноябрь',
        'декабрь',
      ];
      for (var month = 1; month <= 12; month++) {
        expect(
          formatMonthYear(DateOnly(2026, month, 15)),
          startsWith('${nominative[month - 1]} 2026'),
          reason: 'месяц $month',
        );
      }
    });
  });
}
