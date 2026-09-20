import 'package:money_app/core/time/clock.dart';

/// Часы для тестов: показывают заданный момент, пока его не изменят.
final class FixedClock extends Clock {
  FixedClock(this.value);

  DateTime value;

  @override
  DateTime now() => value;

  void advance(Duration duration) {
    value = value.add(duration);
  }
}
