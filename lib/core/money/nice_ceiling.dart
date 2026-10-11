/// Наибольшее значение `int` (2^63 − 1).
const int _maxInt = 9223372036854775807;

/// «Круглый» верх шкалы: наименьшее из 1, 2, 2,5, 5 × 10^n (в минорных
/// единицах, целое), не меньшее [maxMinorUnits]. Для 0 и 1 — 1.
/// Отрицательное значение — [ArgumentError].
///
/// Если следующее «круглое» число не помещается в `int` (больше примерно
/// 5·10^18), возвращается сам [maxMinorUnits]: переполнения нет.
int niceCeiling(int maxMinorUnits) {
  if (maxMinorUnits < 0) {
    throw ArgumentError.value(maxMinorUnits, 'maxMinorUnits', 'Must be >= 0');
  }
  if (maxMinorUnits <= 1) return 1;
  var power = 1;
  while (power <= maxMinorUnits ~/ 10) {
    power *= 10;
  }
  // Множители 1, 2, 2,5, 5, 10 как дроби (числитель, знаменатель).
  const steps = [(1, 1), (2, 1), (5, 2), (5, 1), (10, 1)];
  for (final (num, den) in steps) {
    if (power > _maxInt ~/ num) return maxMinorUnits;
    final candidate = power * num ~/ den;
    if (candidate >= maxMinorUnits) return candidate;
  }
  return maxMinorUnits;
}
