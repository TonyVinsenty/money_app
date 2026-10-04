final String _nbsp = String.fromCharCode(0x00A0);

/// Процент для экрана: «34 %» (неразрывный пробел) или «<1 %», если доля
/// больше нуля, но округлилась до нуля.
String formatPercent(int percent, {required bool isBelowOne}) =>
    isBelowOne ? '<1$_nbsp%' : '$percent$_nbsp%';

/// Процент для скринридера: «34 процента», «меньше 1 процента».
String spokenPercent(int percent, {required bool isBelowOne}) {
  if (isBelowOne) return 'меньше 1 процента';
  return '$percent ${pluralRu(percent, 'процент', 'процента', 'процентов')}';
}

/// Форма слова по числу [n]: 1 (кроме 11) — [one], 2-4 (кроме 12-14) — [few],
/// остальное — [many].
String pluralRu(int n, String one, String few, String many) {
  final lastTwo = n % 100;
  if (lastTwo >= 11 && lastTwo <= 14) return many;
  return switch (n % 10) {
    1 => one,
    2 || 3 || 4 => few,
    _ => many,
  };
}
