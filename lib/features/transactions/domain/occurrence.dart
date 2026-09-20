import 'package:money_app/core/time/clock.dart';
import 'package:money_app/core/time/date_only.dart';

/// Когда произошла операция: день и момент, выведенные из одного источника.
///
/// У операции две величины про одно и то же время (ADR 0004): локальный день
/// [occurredOn] и момент в UTC [occurredAt]. Задавать их руками по отдельности
/// нельзя, иначе получится «день 19 сентября, момент 25 сентября». Поэтому
/// экземпляр создаётся только через [Occurrence.onDay], и локальный день
/// [occurredAt] всегда равен [occurredOn].
final class Occurrence {
  const Occurrence._(this.occurredOn, this.occurredAt);

  /// Выводит обе величины из выбранного пользователем дня [day] и [clock].
  ///
  /// ADR 0004 про момент выбранного (не сегодняшнего) дня молчит, поэтому
  /// принято решение:
  /// - сегодня: момент = `clock.now()` в UTC (настоящее время суток);
  /// - прошлый день: момент = полдень ЭТОГО локального дня, переведённый в UTC.
  ///   Полдень выбран потому, что от него до границ дня далеко: даже при
  ///   сдвиге часового пояса или перехода на летнее время локальный день не
  ///   меняется. Реального времени суток у такой операции нет, для подсказок
  ///   по времени суток она «дневная».
  ///
  /// День позже сегодняшнего — [ArgumentError]: операция это факт, а не план.
  factory Occurrence.onDay(DateOnly day, {required Clock clock}) {
    final now = clock.now();
    final today = DateOnly.fromDateTime(now);
    if (day > today) {
      throw ArgumentError.value(
        day,
        'day',
        'операция не может быть позже сегодняшнего дня ($today)',
      );
    }
    final moment = day == today
        ? now.toUtc()
        : DateTime(day.year, day.month, day.day, 12).toUtc();
    return Occurrence._(day, moment);
  }

  /// Локальный календарный день операции.
  final DateOnly occurredOn;

  /// Момент операции в UTC.
  final DateTime occurredAt;

  @override
  bool operator ==(Object other) =>
      other is Occurrence &&
      other.occurredOn == occurredOn &&
      other.occurredAt == occurredAt;

  @override
  int get hashCode => Object.hash(occurredOn, occurredAt);

  @override
  String toString() => 'Occurrence($occurredOn, $occurredAt)';
}
