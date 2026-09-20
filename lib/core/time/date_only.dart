/// Календарный день без времени и без часового пояса (ADR 0004, раздел 2).
///
/// В отличие от `DateTime` (момент времени) не хранит часы и минуты, поэтому
/// его нельзя случайно сдвинуть переходом на летнее время или сменой пояса.
final class DateOnly implements Comparable<DateOnly> {
  /// Создаёт день; бросает [ArgumentError], если такого дня нет в календаре
  /// (30 февраля, месяц 13, день 0) или год вне диапазона 1..9999.
  ///
  /// Не `const`: проверка выполняется при каждом создании.
  DateOnly(this.year, this.month, this.day) {
    if (year < 1 || year > 9999) {
      throw ArgumentError.value(year, 'year', 'must be in 1..9999');
    }
    // Круговой прогон: DateTime «переполняет» несуществующие даты
    // (31 апреля станет 1 мая), поэтому такие значения не совпадут с исходными.
    final check = DateTime(year, month, day);
    if (check.year != year || check.month != month || check.day != day) {
      throw ArgumentError('Invalid date: $year-$month-$day');
    }
  }

  /// Берёт день из ГГГГММДД (например, `20260919`), как хранится в БД.
  /// Некорректное число (`20260230`, `0`, отрицательное) — [ArgumentError].
  factory DateOnly.fromInt(int value) {
    if (value <= 0) {
      throw ArgumentError.value(value, 'value', 'must be positive');
    }
    return DateOnly(value ~/ 10000, (value ~/ 100) % 100, value % 100);
  }

  /// Берёт ЛОКАЛЬНЫЙ год, месяц и день момента [value].
  ///
  /// `toLocal()` для UTC-момента даёт день в часовом поясе устройства, для
  /// уже локального момента ничего не меняет. Так реализовано правило
  /// ADR 0004: локальный день фиксируется при записи и потом не пересчитывается.
  factory DateOnly.fromDateTime(DateTime value) {
    final local = value.toLocal();
    return DateOnly(local.year, local.month, local.day);
  }

  final int year;
  final int month;
  final int day;

  /// День недели: 1 — понедельник ... 7 — воскресенье (как `DateTime.weekday`).
  int get weekday => toDateTime().weekday;

  /// Локальная полночь этого дня.
  DateTime toDateTime() => DateTime(year, month, day);

  /// Сдвиг на [days] дней (можно отрицательное).
  ///
  /// Только через конструктор `DateTime`, а не `add(Duration(days: n))`:
  /// `Duration` — ровно 24 часа и при переходе на летнее время «съезжает» на час.
  DateOnly addDays(int days) {
    final shifted = DateTime(year, month, day + days);
    return DateOnly(shifted.year, shifted.month, shifted.day);
  }

  /// Число ГГГГММДД для хранения в БД (`20260919`).
  int toInt() => year * 10000 + month * 100 + day;

  @override
  int compareTo(DateOnly other) => toInt().compareTo(other.toInt());

  bool operator <(DateOnly other) => compareTo(other) < 0;

  bool operator >(DateOnly other) => compareTo(other) > 0;

  bool operator <=(DateOnly other) => compareTo(other) <= 0;

  bool operator >=(DateOnly other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is DateOnly &&
      other.year == year &&
      other.month == month &&
      other.day == day;

  @override
  int get hashCode => Object.hash(year, month, day);

  /// Вид `2026-09-19`.
  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}
