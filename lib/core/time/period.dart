import 'package:money_app/core/time/date_only.dart';

/// Период из календарных дней: обе границы ВКЛЮЧИТЕЛЬНО.
///
/// Для запросов по моментам используйте полуинтервал
/// `[startDateTime, endExclusiveDateTime)`.
final class DateRange {
  /// Один день допустим (`start == end`); `end < start` — [ArgumentError].
  /// Это же «свой интервал» пользователя.
  DateRange(this.start, this.end) {
    if (end < start) {
      throw ArgumentError('end ($end) must not be before start ($start)');
    }
  }

  final DateOnly start;
  final DateOnly end;

  bool contains(DateOnly day) => day >= start && day <= end;

  /// Сколько дней в периоде, обе границы считаются.
  int get lengthInDays {
    // Разница считается в UTC, где не бывает перехода на летнее время.
    final from = DateTime.utc(start.year, start.month, start.day);
    final to = DateTime.utc(end.year, end.month, end.day);
    return to.difference(from).inDays + 1;
  }

  /// Локальная полночь первого дня.
  DateTime get startDateTime => start.toDateTime();

  /// Локальная полночь дня ПОСЛЕ последнего: исключающая граница полуинтервала.
  DateTime get endExclusiveDateTime =>
      DateTime(end.year, end.month, end.day + 1);

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => '$start..$end';
}

/// Период из одного дня [day].
DateRange dayRange(DateOnly day) => DateRange(day, day);

/// Неделя, в которую входит [day]. По умолчанию начинается с понедельника
/// (`DateTime.monday`); [firstWeekday] — 1..7 (7 — воскресенье), иначе
/// [ArgumentError].
DateRange weekRange(DateOnly day, {int firstWeekday = DateTime.monday}) {
  if (firstWeekday < DateTime.monday || firstWeekday > DateTime.sunday) {
    throw ArgumentError.value(firstWeekday, 'firstWeekday', 'must be in 1..7');
  }
  final daysSinceStart = (day.weekday - firstWeekday + 7) % 7;
  final start = day.addDays(-daysSinceStart);
  return DateRange(start, start.addDays(6));
}

/// Календарный месяц, в который входит [day].
DateRange monthRange(DateOnly day) {
  // День 0 следующего месяца — это последний день текущего.
  final last = DateTime(day.year, day.month + 1, 0);
  return DateRange(
    DateOnly(day.year, day.month, 1),
    DateOnly(day.year, day.month, last.day),
  );
}

/// Календарный год, в который входит [day].
DateRange yearRange(DateOnly day) =>
    DateRange(DateOnly(day.year, 1, 1), DateOnly(day.year, 12, 31));
