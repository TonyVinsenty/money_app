import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/time/date_only.dart';

Matcher get _throwsArgumentError => throwsA(isA<ArgumentError>());

void main() {
  group('DateOnly: создание', () {
    test('хранит год, месяц и день', () {
      final d = DateOnly(2026, 9, 19);
      expect(d.year, 2026);
      expect(d.month, 9);
      expect(d.day, 19);
    });

    test('29 февраля существует в високосных 2024 и 2000', () {
      expect(DateOnly(2024, 2, 29).day, 29);
      expect(DateOnly(2000, 2, 29).day, 29);
    });

    test('29 февраля в 2026, 2100 и 1900 — ошибка', () {
      expect(() => DateOnly(2026, 2, 29), _throwsArgumentError);
      expect(() => DateOnly(2100, 2, 29), _throwsArgumentError);
      expect(() => DateOnly(1900, 2, 29), _throwsArgumentError);
    });

    test('месяц 0 и 13 — ошибка', () {
      expect(() => DateOnly(2026, 0, 1), _throwsArgumentError);
      expect(() => DateOnly(2026, 13, 1), _throwsArgumentError);
    });

    test('день 0 и 32 — ошибка', () {
      expect(() => DateOnly(2026, 1, 0), _throwsArgumentError);
      expect(() => DateOnly(2026, 1, 32), _throwsArgumentError);
    });

    test('31 апреля — ошибка, 30 апреля и 31 марта — нормально', () {
      expect(() => DateOnly(2026, 4, 31), _throwsArgumentError);
      expect(DateOnly(2026, 4, 30).day, 30);
      expect(DateOnly(2026, 3, 31).day, 31);
    });

    test('год вне 1..9999 — ошибка, крайние годы допустимы', () {
      expect(() => DateOnly(0, 1, 1), _throwsArgumentError);
      expect(() => DateOnly(-1, 1, 1), _throwsArgumentError);
      expect(() => DateOnly(10000, 1, 1), _throwsArgumentError);
      expect(DateOnly(1, 1, 1).year, 1);
      expect(DateOnly(9999, 12, 31).year, 9999);
    });
  });

  group('DateOnly: связь с DateTime', () {
    test('fromDateTime: локальная полночь', () {
      expect(
        DateOnly.fromDateTime(DateTime(2026, 9, 19)),
        DateOnly(2026, 9, 19),
      );
    });

    test('fromDateTime: 23:59:59.999 остаётся в том же дне', () {
      final value = DateTime(2026, 9, 19, 23, 59, 59, 999);
      expect(DateOnly.fromDateTime(value), DateOnly(2026, 9, 19));
    });

    test('fromDateTime: UTC-момент даёт день в поясе устройства', () {
      // Ожидание считаем без DateOnly и без toLocal() в полях: берём смещение
      // пояса машины и прибавляем к UTC-моменту. Получается «настенное»
      // время в поясе устройства (в объекте с пометкой UTC), из которого
      // читаем год/месяц/день. Тест верен в любом поясе: 23:30 UTC — это
      // 19 или 20 сентября в зависимости от смещения, и ожидание это учитывает.
      final value = DateTime.utc(2026, 9, 19, 23, 30);
      final wall = value.add(value.toLocal().timeZoneOffset);

      final result = DateOnly.fromDateTime(value);

      expect(result.year, wall.year);
      expect(result.month, wall.month);
      expect(result.day, wall.day);
    });

    test('toDateTime: локальная полночь', () {
      final value = DateOnly(2026, 9, 19).toDateTime();
      expect(value, DateTime(2026, 9, 19));
      expect(value.isUtc, isFalse);
      expect(value.hour, 0);
      expect(value.minute, 0);
    });
  });

  group('DateOnly.addDays', () {
    test('через границу года: 2026-12-31 + 1 = 2027-01-01', () {
      expect(DateOnly(2026, 12, 31).addDays(1), DateOnly(2027, 1, 1));
    });

    test('через високосный день: 2024-02-28 + 1 = 2024-02-29', () {
      expect(DateOnly(2024, 2, 28).addDays(1), DateOnly(2024, 2, 29));
      expect(DateOnly(2024, 2, 28).addDays(2), DateOnly(2024, 3, 1));
    });

    test('в невисокосном году после 28 февраля идёт 1 марта', () {
      expect(DateOnly(2026, 2, 28).addDays(1), DateOnly(2026, 3, 1));
    });

    test('назад через границу месяца: 2026-03-01 - 1 = 2026-02-28', () {
      expect(DateOnly(2026, 3, 1).addDays(-1), DateOnly(2026, 2, 28));
    });

    test('назад через границу года: 2027-01-01 - 1 = 2026-12-31', () {
      expect(DateOnly(2027, 1, 1).addDays(-1), DateOnly(2026, 12, 31));
    });

    test('+0 возвращает тот же день', () {
      expect(DateOnly(2026, 9, 19).addDays(0), DateOnly(2026, 9, 19));
    });

    test('сдвиг туда и обратно возвращает исходный день', () {
      final starts = [
        DateOnly(2026, 9, 19),
        DateOnly(2024, 2, 29),
        DateOnly(2026, 12, 31),
        DateOnly(2027, 1, 1),
      ];
      for (final start in starts) {
        for (final n in [1, 365, 1000]) {
          expect(start.addDays(n).addDays(-n), start, reason: '$start ±$n');
          expect(start.addDays(-n).addDays(n), start, reason: '$start ∓$n');
        }
      }
    });

    test(
      '+365 от 2026-09-19 — 2027-09-19, +366 от 2024-01-01 — 2025-01-01',
      () {
        expect(DateOnly(2026, 9, 19).addDays(365), DateOnly(2027, 9, 19));
        expect(DateOnly(2024, 1, 1).addDays(366), DateOnly(2025, 1, 1));
      },
    );

    test('выход за пределы 1..9999 — ArgumentError', () {
      expect(() => DateOnly(9999, 12, 31).addDays(1), _throwsArgumentError);
      expect(() => DateOnly(1, 1, 1).addDays(-1), _throwsArgumentError);
    });
  });

  group('DateOnly.weekday', () {
    test('совпадает с DateTime.weekday и лежит в 1..7', () {
      final dates = [
        DateOnly(2026, 9, 19),
        DateOnly(2026, 9, 21),
        DateOnly(2026, 12, 31),
        DateOnly(2024, 2, 29),
      ];
      for (final d in dates) {
        expect(d.weekday, DateTime(d.year, d.month, d.day).weekday);
        expect(d.weekday, inInclusiveRange(1, 7));
      }
    });

    test('семь подряд идущих дней дают 1..7 без повторов', () {
      final start = DateOnly(2026, 9, 14);
      final weekdays = [for (var i = 0; i < 7; i++) start.addDays(i).weekday];
      expect(weekdays.toSet(), {1, 2, 3, 4, 5, 6, 7});
      expect(weekdays.first, DateTime(2026, 9, 14).weekday);
    });
  });

  group('DateOnly: toInt / fromInt', () {
    test('toInt даёт ГГГГММДД', () {
      expect(DateOnly(2026, 9, 19).toInt(), 20260919);
      expect(DateOnly(1, 1, 1).toInt(), 10101);
      expect(DateOnly(9999, 12, 31).toInt(), 99991231);
    });

    test('fromInt разбирает ГГГГММДД', () {
      expect(DateOnly.fromInt(20260919), DateOnly(2026, 9, 19));
    });

    test('fromInt(toInt) возвращает исходную дату', () {
      final dates = [
        DateOnly(1, 1, 1),
        DateOnly(2000, 2, 29),
        DateOnly(2024, 2, 29),
        DateOnly(2026, 1, 1),
        DateOnly(2026, 9, 19),
        DateOnly(2026, 12, 31),
        DateOnly(9999, 12, 31),
      ];
      for (final d in dates) {
        expect(DateOnly.fromInt(d.toInt()), d);
      }
    });

    test('некорректные числа — ArgumentError', () {
      for (final bad in [20260230, 20261301, 20260900, 20260100, 0, -1]) {
        expect(
          () => DateOnly.fromInt(bad),
          _throwsArgumentError,
          reason: '$bad',
        );
      }
      expect(() => DateOnly.fromInt(99999999), _throwsArgumentError);
      expect(() => DateOnly.fromInt(-20260919), _throwsArgumentError);
      expect(() => DateOnly.fromInt(202609190), _throwsArgumentError);
    });

    test('числа сравниваются так же, как даты', () {
      expect(
        DateOnly(2026, 12, 31).toInt() < DateOnly(2027, 1, 1).toInt(),
        isTrue,
      );
    });
  });

  group('DateOnly: сравнение и вывод', () {
    test('sort() упорядочивает по возрастанию', () {
      final list = [
        DateOnly(2026, 12, 31),
        DateOnly(2026, 1, 5),
        DateOnly(2025, 12, 31),
        DateOnly(2026, 1, 4),
      ]..sort();
      expect(list, [
        DateOnly(2025, 12, 31),
        DateOnly(2026, 1, 4),
        DateOnly(2026, 1, 5),
        DateOnly(2026, 12, 31),
      ]);
    });

    test('операторы <, >, <=, >=', () {
      final a = DateOnly(2026, 9, 19);
      final b = DateOnly(2026, 9, 20);
      final same = DateOnly(2026, 9, 19);
      expect(a < b, isTrue);
      expect(b > a, isTrue);
      expect(a < same, isFalse);
      expect(a <= same, isTrue);
      expect(a >= same, isTrue);
      expect(a >= b, isFalse);
      expect(b <= a, isFalse);
    });

    test('compareTo', () {
      expect(DateOnly(2026, 9, 19).compareTo(DateOnly(2026, 9, 19)), 0);
      expect(
        DateOnly(2026, 9, 19).compareTo(DateOnly(2026, 9, 20)),
        isNegative,
      );
      expect(
        DateOnly(2026, 9, 20).compareTo(DateOnly(2026, 9, 19)),
        isPositive,
      );
    });

    test('== и hashCode', () {
      final a = DateOnly(2026, 9, 19);
      final b = DateOnly(2026, 9, 19);
      expect(a == b, isTrue);
      expect(a.hashCode, b.hashCode);
      expect(a == DateOnly(2026, 9, 20), isFalse);
      expect(a == DateOnly(2026, 10, 19), isFalse);
      expect(a == DateOnly(2025, 9, 19), isFalse);
      expect({a, b}, hasLength(1));
    });

    test('toString в виде 2026-09-19', () {
      expect(DateOnly(2026, 9, 19).toString(), '2026-09-19');
      expect(DateOnly(2026, 1, 5).toString(), '2026-01-05');
      expect(DateOnly(999, 3, 7).toString(), '0999-03-07');
    });
  });
}
