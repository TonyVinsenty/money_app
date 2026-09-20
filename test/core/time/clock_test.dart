import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/core/time/date_only.dart';

import '../../support/fixed_clock.dart';

void main() {
  group('FixedClock', () {
    test('now() возвращает заданный момент', () {
      final moment = DateTime(2026, 9, 19, 12);
      expect(FixedClock(moment).now(), moment);
    });

    test('today() — день по локальному времени', () {
      final clock = FixedClock(DateTime(2026, 9, 19, 12, 30));
      expect(clock.today(), DateOnly(2026, 9, 19));
    });

    test('23:59:59.999 — ещё тот же день', () {
      final clock = FixedClock(DateTime(2026, 9, 19, 23, 59, 59, 999));
      expect(clock.today(), DateOnly(2026, 9, 19));
    });

    test('00:00:00 следующего дня — уже следующий день', () {
      final clock = FixedClock(DateTime(2026, 9, 20));
      expect(clock.today(), DateOnly(2026, 9, 20));
    });

    test('граница года: 31 декабря 23:59:59.999 и 1 января 00:00', () {
      final clock = FixedClock(DateTime(2026, 12, 31, 23, 59, 59, 999));
      expect(clock.today(), DateOnly(2026, 12, 31));
      clock.value = DateTime(2027);
      expect(clock.today(), DateOnly(2027, 1, 1));
    });

    // Здесь время в UTC: сложение Duration с UTC-моментом всегда точное, а
    // локальное время могло бы «прыгнуть» на час при переходе на летнее время
    // в поясе машины. Поэтому тест не зависит от пояса, где его запускают.
    test('advance двигает время: now() сдвигается ровно на заданный шаг', () {
      final clock = FixedClock(DateTime.utc(2026, 9, 19, 23));
      clock.advance(const Duration(hours: 2));
      expect(clock.now(), DateTime.utc(2026, 9, 20, 1));
    });

    test('advance на двое суток сдвигает today() ровно на два дня', () {
      final clock = FixedClock(DateTime.utc(2026, 9, 19, 12));
      final before = clock.today();
      clock.advance(const Duration(hours: 48));
      expect(clock.today(), before.addDays(2));
    });

    test('FixedClock можно использовать как Clock', () {
      final Clock clock = FixedClock(DateTime(2026, 9, 19));
      expect(clock.today(), DateOnly(2026, 9, 19));
    });
  });

  group('SystemClock', () {
    test('now() близко к DateTime.now()', () {
      final before = DateTime.now();
      final value = const SystemClock().now();
      final after = DateTime.now();
      expect(
        value.isBefore(before.subtract(const Duration(seconds: 5))),
        isFalse,
      );
      expect(value.isAfter(after.add(const Duration(seconds: 5))), isFalse);
    });

    test('today() совпадает с сегодняшним днём системы', () {
      final before = DateOnly.fromDateTime(DateTime.now());
      final today = const SystemClock().today();
      final after = DateOnly.fromDateTime(DateTime.now());
      // Между вызовами могла пройти полночь, поэтому допускаем оба дня.
      expect(today >= before && today <= after, isTrue);
    });
  });
}
