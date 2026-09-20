import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/database/converters/date_only_converter.dart';
import 'package:money_app/core/time/date_only.dart';

void main() {
  const converter = DateOnlyConverter();

  group('toSql', () {
    test('даёт ГГГГММДД', () {
      expect(converter.toSql(DateOnly(2026, 9, 19)), 20260919);
      expect(converter.toSql(DateOnly(2024, 2, 29)), 20240229);
      expect(converter.toSql(DateOnly(2025, 12, 31)), 20251231);
    });

    test('границы диапазона DateOnly', () {
      expect(converter.toSql(DateOnly(1, 1, 1)), 10101);
      expect(converter.toSql(DateOnly(9999, 12, 31)), 99991231);
    });
  });

  group('туда-обратно', () {
    final dates = <DateOnly>[
      DateOnly(1, 1, 1),
      DateOnly(9999, 12, 31),
      DateOnly(2024, 2, 29),
      DateOnly(2023, 2, 28),
      DateOnly(2025, 12, 31),
      DateOnly(2026, 1, 1),
      DateOnly(2026, 9, 19),
      DateOnly(2000, 2, 29),
      DateOnly(1900, 2, 28),
    ];

    for (final date in dates) {
      test('$date', () {
        expect(converter.fromSql(converter.toSql(date)), date);
      });
    }
  });

  group('fromSql', () {
    test('читает ГГГГММДД', () {
      expect(converter.fromSql(20260919), DateOnly(2026, 9, 19));
    });

    const garbage = <int>[
      0,
      -1,
      -20260919,
      20260230,
      20261301,
      20260001,
      20260100,
      20260132,
      20230229,
      19000229,
      99999999,
      12345,
    ];

    for (final value in garbage) {
      test('мусор $value даёт FormatException с этим значением', () {
        expect(
          () => converter.fromSql(value),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              allOf(contains('DateOnly'), contains('$value')),
            ),
          ),
        );
      });
    }

    test('точное сообщение', () {
      expect(
        () => converter.fromSql(20260230),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Bad DateOnly value in database: 20260230',
          ),
        ),
      );
    });
  });
}
