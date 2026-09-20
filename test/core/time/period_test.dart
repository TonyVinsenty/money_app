import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';

Matcher get _throwsArgumentError => throwsA(isA<ArgumentError>());

DateRange _range(int y1, int m1, int d1, int y2, int m2, int d2) =>
    DateRange(DateOnly(y1, m1, d1), DateOnly(y2, m2, d2));

void main() {
  group('DateRange: свой интервал', () {
    final september = _range(2026, 9, 1, 2026, 9, 30);

    test('включает обе границы, но не соседние дни', () {
      expect(september.contains(DateOnly(2026, 9, 1)), isTrue);
      expect(september.contains(DateOnly(2026, 9, 30)), isTrue);
      expect(september.contains(DateOnly(2026, 9, 15)), isTrue);
      expect(september.contains(DateOnly(2026, 8, 31)), isFalse);
      expect(september.contains(DateOnly(2026, 10, 1)), isFalse);
    });

    test('lengthInDays считает обе границы', () {
      expect(september.lengthInDays, 30);
    });

    test('один день допустим', () {
      final one = _range(2026, 9, 19, 2026, 9, 19);
      expect(one.lengthInDays, 1);
      expect(one.contains(DateOnly(2026, 9, 19)), isTrue);
      expect(one.contains(DateOnly(2026, 9, 20)), isFalse);
    });

    test('end раньше start — ArgumentError', () {
      expect(() => _range(2026, 9, 2, 2026, 9, 1), _throwsArgumentError);
    });

    test('== и hashCode и toString', () {
      final a = _range(2026, 9, 1, 2026, 9, 30);
      expect(a, september);
      expect(a.hashCode, september.hashCode);
      expect(a == _range(2026, 9, 1, 2026, 9, 29), isFalse);
      expect(a == _range(2026, 8, 31, 2026, 9, 30), isFalse);
      expect(a.toString(), '2026-09-01..2026-09-30');
    });

    test('lengthInDays через границу года и високосный день', () {
      expect(_range(2026, 12, 25, 2027, 1, 5).lengthInDays, 12);
      expect(_range(2024, 2, 28, 2024, 3, 1).lengthInDays, 3);
      expect(_range(2026, 2, 28, 2026, 3, 1).lengthInDays, 2);
    });
  });

  group('DateRange: моменты (полуинтервал)', () {
    test('startDateTime — локальная полночь первого дня', () {
      expect(
        _range(2026, 9, 1, 2026, 9, 30).startDateTime,
        DateTime(2026, 9, 1),
      );
    });

    test('endExclusive месяца — полночь 1-го числа следующего месяца', () {
      final range = monthRange(DateOnly(2026, 9, 10));
      expect(range.endExclusiveDateTime, DateTime(2026, 10, 1));
    });

    test('endExclusive декабря — 1 января следующего года', () {
      final range = monthRange(DateOnly(2026, 12, 10));
      expect(range.endExclusiveDateTime, DateTime(2027));
    });

    test('23:59:59.999 последнего дня внутри, следующая миллисекунда нет', () {
      final range = monthRange(DateOnly(2026, 9, 10));
      final lastMoment = DateTime(2026, 9, 30, 23, 59, 59, 999);
      final nextMoment = lastMoment.add(const Duration(milliseconds: 1));
      bool inside(DateTime t) =>
          !t.isBefore(range.startDateTime) &&
          t.isBefore(range.endExclusiveDateTime);
      expect(inside(lastMoment), isTrue);
      expect(inside(nextMoment), isFalse);
      expect(inside(DateTime(2026, 9, 1)), isTrue);
      expect(inside(DateTime(2026, 8, 31, 23, 59, 59, 999)), isFalse);
    });

    test('endExclusive одного дня — полночь следующего', () {
      expect(
        dayRange(DateOnly(2026, 12, 31)).endExclusiveDateTime,
        DateTime(2027),
      );
    });
  });

  group('dayRange', () {
    test('период из одного дня', () {
      final d = DateOnly(2026, 9, 19);
      final range = dayRange(d);
      expect(range.start, d);
      expect(range.end, d);
      expect(range.lengthInDays, 1);
    });
  });

  group('weekRange', () {
    final monday = DateOnly(2026, 9, 14);
    final sunday = DateOnly(2026, 9, 20);

    test('проверка исходных данных: 14 сентября — понедельник', () {
      expect(DateTime(2026, 9, 14).weekday, DateTime.monday);
      expect(DateTime(2026, 9, 20).weekday, DateTime.sunday);
    });

    test(
      'по умолчанию неделя с понедельника: любой из 7 дней даёт одну пару',
      () {
        for (var i = 0; i < 7; i++) {
          final range = weekRange(monday.addDays(i));
          expect(range.start, monday, reason: 'день №$i');
          expect(range.end, sunday, reason: 'день №$i');
          expect(range.start.weekday, DateTime.monday);
          expect(range.end.weekday, DateTime.sunday);
          expect(range.lengthInDays, 7);
        }
      },
    );

    test('соседние недели не пересекаются', () {
      final next = weekRange(sunday.addDays(1));
      expect(next.start, DateOnly(2026, 9, 21));
      expect(next.end, DateOnly(2026, 9, 27));
      final previous = weekRange(monday.addDays(-1));
      expect(previous.start, DateOnly(2026, 9, 7));
      expect(previous.end, DateOnly(2026, 9, 13));
    });

    test('через границу месяца и года: 2026-12-31 → 28 декабря..3 января', () {
      expect(DateTime(2026, 12, 31).weekday, DateTime.thursday);
      final range = weekRange(DateOnly(2026, 12, 31));
      expect(range.start, DateOnly(2026, 12, 28));
      expect(range.end, DateOnly(2027, 1, 3));
      expect(range.contains(DateOnly(2027, 1, 1)), isTrue);
    });

    test('воскресенье как первый день недели', () {
      // Суббота 2026-09-19 при неделе с воскресенья: 13..19 сентября.
      expect(DateTime(2026, 9, 19).weekday, DateTime.saturday);
      final range = weekRange(
        DateOnly(2026, 9, 19),
        firstWeekday: DateTime.sunday,
      );
      expect(range.start, DateOnly(2026, 9, 13));
      expect(range.start.weekday, DateTime.sunday);
      expect(range.end, DateOnly(2026, 9, 19));
      expect(range.lengthInDays, 7);
    });

    test('воскресенье само начинает неделю при firstWeekday = воскресенье', () {
      final range = weekRange(sunday, firstWeekday: DateTime.sunday);
      expect(range.start, sunday);
      expect(range.end, DateOnly(2026, 9, 26));
    });

    test('в той же дате понедельник и воскресенье дают разные недели', () {
      // Воскресенье 20 сентября: по умолчанию последний день недели,
      // при воскресной настройке — первый.
      expect(weekRange(sunday).start, monday);
      expect(weekRange(sunday, firstWeekday: DateTime.sunday).start, sunday);
    });

    test('firstWeekday 0 и 8 — ArgumentError', () {
      expect(() => weekRange(monday, firstWeekday: 0), _throwsArgumentError);
      expect(() => weekRange(monday, firstWeekday: 8), _throwsArgumentError);
    });
  });

  group('monthRange', () {
    const commonLengths = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

    test('все 12 месяцев 2026 (невисокосный)', () {
      for (var m = 1; m <= 12; m++) {
        final range = monthRange(DateOnly(2026, m, 15));
        expect(range.start, DateOnly(2026, m, 1), reason: 'месяц $m');
        expect(range.end.day, commonLengths[m - 1], reason: 'месяц $m');
        expect(range.end.month, m);
        expect(range.lengthInDays, commonLengths[m - 1]);
      }
    });

    test('все 12 месяцев 2024 (високосный)', () {
      for (var m = 1; m <= 12; m++) {
        final expected = m == 2 ? 29 : commonLengths[m - 1];
        final range = monthRange(DateOnly(2024, m, 1));
        expect(range.start, DateOnly(2024, m, 1), reason: 'месяц $m');
        expect(range.end.day, expected, reason: 'месяц $m');
        expect(range.lengthInDays, expected);
      }
    });

    test('февраль: 2024 и 2000 — 29 дней, 2026 и 2100 — 28', () {
      expect(monthRange(DateOnly(2024, 2, 10)).end, DateOnly(2024, 2, 29));
      expect(monthRange(DateOnly(2000, 2, 10)).end, DateOnly(2000, 2, 29));
      expect(monthRange(DateOnly(2026, 2, 10)).end, DateOnly(2026, 2, 28));
      expect(monthRange(DateOnly(2100, 2, 10)).end, DateOnly(2100, 2, 28));
      expect(monthRange(DateOnly(2026, 2, 10)).start, DateOnly(2026, 2, 1));
    });

    test('любой день месяца даёт один и тот же период', () {
      final first = monthRange(DateOnly(2026, 9, 1));
      expect(monthRange(DateOnly(2026, 9, 17)), first);
      expect(monthRange(DateOnly(2026, 9, 30)), first);
    });

    test('декабрь заканчивается 31-м', () {
      final range = monthRange(DateOnly(2026, 12, 5));
      expect(range.start, DateOnly(2026, 12, 1));
      expect(range.end, DateOnly(2026, 12, 31));
    });

    test('крайний месяц 9999-12 не ломается', () {
      final range = monthRange(DateOnly(9999, 12, 1));
      expect(range.end, DateOnly(9999, 12, 31));
    });
  });

  group('yearRange', () {
    test('невисокосный 2026: 365 дней, с 1 января по 31 декабря', () {
      final range = yearRange(DateOnly(2026, 9, 19));
      expect(range.start, DateOnly(2026, 1, 1));
      expect(range.end, DateOnly(2026, 12, 31));
      expect(range.lengthInDays, 365);
    });

    test('високосный 2024: 366 дней', () {
      final range = yearRange(DateOnly(2024, 2, 29));
      expect(range.start, DateOnly(2024, 1, 1));
      expect(range.end, DateOnly(2024, 12, 31));
      expect(range.lengthInDays, 366);
    });

    test('endExclusive года — 1 января следующего', () {
      expect(
        yearRange(DateOnly(2026, 6, 1)).endExclusiveDateTime,
        DateTime(2027),
      );
    });
  });
}
