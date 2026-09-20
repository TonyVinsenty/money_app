import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/transactions/domain/occurrence.dart';

import '../../../support/fixed_clock.dart';

void main() {
  // Местное время устройства: день считаем по нему, как и приложение.
  final clock = FixedClock(DateTime(2026, 9, 20, 15, 30));
  final today = DateOnly(2026, 9, 20);

  /// Главный инвариант: день всегда равен локальному дню момента.
  void expectConsistent(Occurrence o) {
    expect(o.occurredAt.isUtc, isTrue);
    expect(DateOnly.fromDateTime(o.occurredAt), o.occurredOn);
  }

  test('сегодня: момент — «сейчас» в UTC', () {
    final o = Occurrence.onDay(today, clock: clock);

    expect(o.occurredOn, today);
    expect(o.occurredAt, clock.now().toUtc());
    expectConsistent(o);
  });

  test('вчера: момент — полдень вчерашнего дня по местному времени', () {
    final o = Occurrence.onDay(DateOnly(2026, 9, 19), clock: clock);

    expect(o.occurredOn, DateOnly(2026, 9, 19));
    expect(o.occurredAt, DateTime(2026, 9, 19, 12).toUtc());
    expectConsistent(o);
  });

  test('день согласован с моментом для любого дня недавнего прошлого', () {
    for (var back = 0; back <= 800; back++) {
      expectConsistent(Occurrence.onDay(today.addDays(-back), clock: clock));
    }
  });

  test('сегодня близко к полуночи: день остаётся сегодняшним', () {
    for (final time in [
      DateTime(2026, 9, 20, 0, 1),
      DateTime(2026, 9, 20, 23, 59),
    ]) {
      final c = FixedClock(time);
      final o = Occurrence.onDay(c.today(), clock: c);
      expect(o.occurredOn, DateOnly(2026, 9, 20));
      expectConsistent(o);
    }
  });

  test('часы в UTC тоже дают согласованную пару', () {
    final c = FixedClock(DateTime.utc(2026, 9, 20, 12));
    final o = Occurrence.onDay(c.today(), clock: c);

    expect(o.occurredAt, DateTime.utc(2026, 9, 20, 12));
    expectConsistent(o);
  });

  test('день позже сегодняшнего — ArgumentError', () {
    expect(
      () => Occurrence.onDay(DateOnly(2026, 9, 21), clock: clock),
      throwsArgumentError,
    );
  });

  test('равенство по обеим величинам', () {
    expect(
      Occurrence.onDay(today, clock: clock),
      Occurrence.onDay(today, clock: clock),
    );
    expect(
      Occurrence.onDay(today, clock: clock),
      isNot(Occurrence.onDay(DateOnly(2026, 9, 19), clock: clock)),
    );
  });
}
