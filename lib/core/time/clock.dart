import 'package:money_app/core/time/date_only.dart';

/// Источник «сейчас» (ADR 0004). Код, которому нужно текущее время, получает
/// [Clock] параметром, а в тестах подставляется фиксированный.
abstract class Clock {
  const Clock();

  DateTime now();

  /// Сегодняшний календарный день по местному времени.
  DateOnly today() => DateOnly.fromDateTime(now());
}

/// Настоящие системные часы.
final class SystemClock extends Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}
