import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/domain/recurring_schedule.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

RecurringPayment make({
  required RepeatUnit unit,
  int every = 1,
  required DateOnly startsOn,
  DateOnly? endsOn,
  DateTime? deletedAt,
}) {
  return RecurringPayment(
    id: 'p1',
    title: 'Платёж',
    type: TransactionType.expense,
    amount: Money.fromMinor(100, 'RUB'),
    categoryId: 'c1',
    unit: unit,
    every: every,
    startsOn: startsOn,
    endsOn: endsOn,
    deletedAt: deletedAt,
  );
}

DateOnly d(int y, int m, int day) => DateOnly(y, m, day);

void main() {
  group('месяц', () {
    final jan31 = make(unit: RepeatUnit.month, startsOn: d(2027, 1, 31));

    test('31 января -> 28 февраля -> 31 марта -> 30 апреля (невисокосный)', () {
      expect(dueDates(jan31, d(2027, 1, 1), d(2027, 5, 31)), [
        d(2027, 1, 31),
        d(2027, 2, 28),
        d(2027, 3, 31),
        d(2027, 4, 30),
        d(2027, 5, 31),
      ]);
    });

    test('в високосный год февраль даёт 29-е', () {
      final p = make(unit: RepeatUnit.month, startsOn: d(2028, 1, 31));
      expect(dueDates(p, d(2028, 2, 1), d(2028, 3, 31)), [
        d(2028, 2, 29),
        d(2028, 3, 31),
      ]);
    });

    test('каждые 3 месяца с 30-го: февраль зажимается, дальше снова 30-е', () {
      final p = make(
        unit: RepeatUnit.month,
        every: 3,
        startsOn: d(2026, 11, 30),
      );
      expect(dueDates(p, d(2026, 1, 1), d(2027, 11, 30)), [
        d(2026, 11, 30),
        d(2027, 2, 28),
        d(2027, 5, 30),
        d(2027, 8, 30),
        d(2027, 11, 30),
      ]);
    });

    test('через Новый год', () {
      final p = make(unit: RepeatUnit.month, startsOn: d(2026, 11, 5));
      expect(dueDates(p, d(2026, 12, 1), d(2027, 1, 31)), [
        d(2026, 12, 5),
        d(2027, 1, 5),
      ]);
    });

    test('nextDueAfter идёт от якоря, а не от прошлой даты', () {
      expect(nextDueAfter(jan31, d(2027, 2, 28)), d(2027, 3, 31));
      expect(nextDueAfter(jan31, d(2027, 1, 31)), d(2027, 2, 28));
    });
  });

  group('год', () {
    final feb29 = make(unit: RepeatUnit.year, startsOn: d(2024, 2, 29));

    test('29 февраля -> 28 февраля в невисокосный -> 29 в високосный', () {
      expect(dueDates(feb29, d(2024, 1, 1), d(2028, 12, 31)), [
        d(2024, 2, 29),
        d(2025, 2, 28),
        d(2026, 2, 28),
        d(2027, 2, 28),
        d(2028, 2, 29),
      ]);
    });

    test('каждые 2 года', () {
      final p = make(unit: RepeatUnit.year, every: 2, startsOn: d(2026, 3, 1));
      expect(dueDates(p, d(2026, 1, 1), d(2031, 1, 1)), [
        d(2026, 3, 1),
        d(2028, 3, 1),
        d(2030, 3, 1),
      ]);
    });
  });

  group('неделя', () {
    test('каждые 2 недели через Новый год', () {
      final p = make(
        unit: RepeatUnit.week,
        every: 2,
        startsOn: d(2026, 12, 18),
      );
      final dates = dueDates(p, d(2026, 12, 1), d(2027, 1, 31));
      expect(dates, [
        d(2026, 12, 18),
        d(2027, 1, 1),
        d(2027, 1, 15),
        d(2027, 1, 29),
      ]);
      expect(dates.map((x) => x.weekday).toSet(), {5});
    });

    test('переход на летнее время не сдвигает дни', () {
      final p = make(unit: RepeatUnit.week, startsOn: d(2027, 3, 20));
      expect(dueDates(p, d(2027, 3, 20), d(2027, 4, 10)), [
        d(2027, 3, 20),
        d(2027, 3, 27),
        d(2027, 4, 3),
        d(2027, 4, 10),
      ]);
    });
  });

  group('границы', () {
    test('endsOn ровно в день платежа - платёж входит', () {
      final p = make(
        unit: RepeatUnit.month,
        startsOn: d(2026, 11, 5),
        endsOn: d(2027, 1, 5),
      );
      expect(dueDates(p, d(2026, 1, 1), d(2030, 1, 1)), [
        d(2026, 11, 5),
        d(2026, 12, 5),
        d(2027, 1, 5),
      ]);
      expect(nextDueAfter(p, d(2026, 12, 5)), d(2027, 1, 5));
      expect(nextDueAfter(p, d(2027, 1, 5)), isNull);
    });

    test('endsOn за день до платежа - платёж не входит', () {
      final p = make(
        unit: RepeatUnit.month,
        startsOn: d(2026, 11, 5),
        endsOn: d(2027, 1, 4),
      );
      expect(dueDates(p, d(2026, 1, 1), d(2030, 1, 1)), [
        d(2026, 11, 5),
        d(2026, 12, 5),
      ]);
      expect(nextDueAfter(p, d(2026, 12, 5)), isNull);
    });

    test('отрезок целиком до startsOn - пусто, а следующий - startsOn', () {
      final p = make(unit: RepeatUnit.week, startsOn: d(2026, 11, 5));
      expect(dueDates(p, d(2026, 10, 1), d(2026, 11, 4)), isEmpty);
      expect(nextDueAfter(p, d(2026, 10, 1)), d(2026, 11, 5));
      expect(nextDueAfter(p, d(2026, 11, 4)), d(2026, 11, 5));
    });

    test('отрезок включает обе границы, startsOn входит', () {
      final p = make(unit: RepeatUnit.week, startsOn: d(2026, 11, 5));
      expect(dueDates(p, d(2026, 11, 5), d(2026, 11, 12)), [
        d(2026, 11, 5),
        d(2026, 11, 12),
      ]);
      expect(dueDates(p, d(2026, 11, 6), d(2026, 11, 11)), isEmpty);
    });

    test('from позже to - пусто', () {
      final p = make(unit: RepeatUnit.week, startsOn: d(2026, 11, 5));
      expect(dueDates(p, d(2026, 11, 12), d(2026, 11, 5)), isEmpty);
    });

    test('удалённый платёж дат не даёт', () {
      final p = make(
        unit: RepeatUnit.week,
        startsOn: d(2026, 11, 5),
        deletedAt: DateTime.utc(2026, 11, 1),
      );
      expect(dueDates(p, d(2026, 1, 1), d(2030, 1, 1)), isEmpty);
      expect(nextDueAfter(p, d(2026, 1, 1)), isNull);
    });

    test('конец календаря (год 9999) не падает', () {
      final p = make(unit: RepeatUnit.year, startsOn: d(9998, 6, 1));
      expect(dueDates(p, d(9998, 1, 1), d(9999, 12, 31)), [
        d(9998, 6, 1),
        d(9999, 6, 1),
      ]);
      expect(nextDueAfter(p, d(9999, 6, 1)), isNull);
    });
  });

  test('в расписании не используется Duration', () {
    final source = File('lib/features/recurring/domain/recurring_schedule.dart')
        .readAsStringSync();
    final code = source
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
    expect(code.contains('Duration'), isFalse);
  });
}
