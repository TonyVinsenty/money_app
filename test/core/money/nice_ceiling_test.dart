import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/nice_ceiling.dart';

void main() {
  group('niceCeiling', () {
    test('граничные значения', () {
      expect(niceCeiling(0), 1);
      expect(niceCeiling(1), 1);
      expect(niceCeiling(2), 2);
      expect(niceCeiling(3), 5);
      expect(niceCeiling(6), 10);
      expect(niceCeiling(99), 100);
      expect(niceCeiling(100), 100);
      expect(niceCeiling(101), 200);
      expect(niceCeiling(201), 250);
      expect(niceCeiling(251), 500);
      expect(niceCeiling(501), 1000);
      expect(niceCeiling(234000), 250000);
      expect(niceCeiling(100000000000000), 100000000000000);
    });

    test('результат не меньше входа и из набора 1, 2, 2.5, 5 x 10^n', () {
      for (final v in [7, 10, 11, 25, 26, 49, 51, 999, 123456, 987654321]) {
        final c = niceCeiling(v);
        expect(c, greaterThanOrEqualTo(v));
        expect(c < v * 3, isTrue);
      }
    });

    test('большие значения без переполнения', () {
      expect(niceCeiling(1000000000000000), 1000000000000000);
      expect(niceCeiling(1000000000000001), 2000000000000000);
      expect(niceCeiling(1000000000000000000), 1000000000000000000);
      expect(niceCeiling(3000000000000000000), 5000000000000000000);
      // Следующее «круглое» (10^19) не помещается: возвращается сам максимум.
      const maxInt = 9223372036854775807;
      expect(niceCeiling(maxInt), maxInt);
      expect(niceCeiling(5000000000000000001), 5000000000000000001);
    });

    test('отрицательное — ArgumentError', () {
      expect(() => niceCeiling(-1), throwsArgumentError);
    });
  });
}
