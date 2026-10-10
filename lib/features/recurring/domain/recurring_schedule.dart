import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';

/// Даты платежей [payment] в отрезке от [from] до [to] включительно, по
/// возрастанию (ADR 0011, п. 3).
///
/// Учитывает `startsOn` и `endsOn` (включительно). Удалённый платёж дат не
/// даёт. Если [from] позже [to], список пустой.
List<DateOnly> dueDates(RecurringPayment payment, DateOnly from, DateOnly to) {
  if (payment.isDeleted || from > to) return const [];
  final result = <DateOnly>[];
  for (var k = 0; ; k++) {
    final date = _nthDate(payment, k);
    if (date == null || date > to) break;
    final end = payment.endsOn;
    if (end != null && date > end) break;
    if (date >= from) result.add(date);
  }
  return result;
}

/// Ближайшая дата платежа строго после [day]; `null`, если платёж удалён или
/// уже закончился (ADR 0011, п. 3).
DateOnly? nextDueAfter(RecurringPayment payment, DateOnly day) {
  if (payment.isDeleted) return null;
  for (var k = 0; ; k++) {
    final date = _nthDate(payment, k);
    if (date == null) return null;
    final end = payment.endsOn;
    if (end != null && date > end) return null;
    if (date > day) return date;
  }
}

/// k-й платёж (k = 0 - `startsOn`), считается от якоря, а не от предыдущей
/// даты. `null`, если дата выходит за год 9999.
///
/// Арифметика только через конструктор `DateTime`, без `Duration` (ADR 0004).
DateOnly? _nthDate(RecurringPayment payment, int k) {
  final start = payment.startsOn;
  final step = payment.every * k;
  switch (payment.unit) {
    case RepeatUnit.week:
      final shifted = DateTime(start.year, start.month, start.day + 7 * step);
      return _build(shifted.year, shifted.month, shifted.day);
    case RepeatUnit.month:
      final total = start.year * 12 + (start.month - 1) + step;
      return _clamped(total ~/ 12, total % 12 + 1, start.day);
    case RepeatUnit.year:
      return _clamped(start.year + step, start.month, start.day);
  }
}

/// День [day] месяца, а если в месяце его нет - последний день месяца.
DateOnly? _clamped(int year, int month, int day) {
  // Нулевой день следующего месяца - последний день этого.
  final lastDay = DateTime(year, month + 1, 0).day;
  return _build(year, month, day < lastDay ? day : lastDay);
}

DateOnly? _build(int year, int month, int day) {
  if (year > 9999) return null;
  return DateOnly(year, month, day);
}
