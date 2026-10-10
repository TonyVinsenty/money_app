/// «Круглый» верх шкалы: наименьшее из 1, 2, 2,5, 5 × 10^n (в минорных
/// единицах, целое), не меньшее [maxMinorUnits]. Для 0 и 1 — 1.
/// Отрицательное значение — [ArgumentError].
int niceCeiling(int maxMinorUnits) {
  if (maxMinorUnits < 0) {
    throw ArgumentError.value(maxMinorUnits, 'maxMinorUnits', 'Must be >= 0');
  }
  if (maxMinorUnits <= 1) return 1;
  var power = 1;
  while (power * 10 <= maxMinorUnits) {
    power *= 10;
  }
  final candidates = [
    power,
    power * 2,
    if (power >= 10) power * 5 ~/ 2,
    power * 5,
    power * 10,
  ];
  return candidates.firstWhere((c) => c >= maxMinorUnits);
}
