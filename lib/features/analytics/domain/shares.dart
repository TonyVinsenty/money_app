import 'package:money_app/core/money/money.dart';
import 'package:money_app/features/analytics/domain/category_totals.dart';

/// Сколько именных секторов максимум на кольце (по размеру палитры).
const int maxNamedSlices = 8;

/// Сектор мелкий, если его доля меньше этого процента (сравнение целое).
const int smallSharePercent = 3;

/// Доля в целых процентах.
final class PercentShare {
  const PercentShare({required this.percent, required this.isBelowOne});

  /// Целый процент от 0 до 100. `null`, если общий итог равен нулю и процентов
  /// нет.
  final int? percent;

  /// Сумма больше нуля, а процент округлился до нуля. На экране такая доля
  /// показывается как «<1 %», а не как «0 %». В [percent] при этом стоит 0.
  final bool isBelowOne;
}

/// Сектор кольца: одна именная категория или группа «Остальное».
final class ChartSlice {
  const ChartSlice({
    required this.categoryIds,
    required this.amount,
    required this.share,
    required this.isOther,
  });

  /// Категории сектора. У именного сектора одна, у «Остальное» — все входящие.
  final List<String> categoryIds;

  /// Сумма сектора (для «Остальное» — сумма входящих).
  final Money amount;

  /// Процент сектора. Для «Остальное» — сумма процентов входящих категорий.
  final PercentShare share;

  /// Группа «Остальное».
  final bool isOther;
}

/// Проценты долей [amounts] методом наибольшего остатка.
///
/// Каждая доля получает целую часть `сумма × 100 ~/ итог`. Недостающие до 100
/// единицы раздаются по одной долям с наибольшим остатком; при равном остатке
/// раньше идёт доля, которая выше в списке. Поэтому сумма процентов всегда
/// ровно 100, когда итог больше нуля.
///
/// Если итог равен нулю, процентов нет: в каждом элементе `percent == null`.
/// Пустой список даёт пустой результат. Суммы должны быть одной валюты и не
/// отрицательными, иначе [ArgumentError].
List<PercentShare> percentShares(List<Money> amounts) {
  if (amounts.isEmpty) return const [];
  final currency = amounts.first.currency;
  var total = 0;
  for (final amount in amounts) {
    if (amount.currency != currency) {
      throw ArgumentError.value(
        amount.currency,
        'currency',
        'Expected $currency for every amount',
      );
    }
    if (amount.isNegative) {
      throw ArgumentError.value(amount, 'amounts', 'Must not be negative');
    }
    total += amount.minorUnits;
  }
  if (total == 0) {
    return List<PercentShare>.filled(
      amounts.length,
      const PercentShare(percent: null, isBelowOne: false),
      growable: false,
    );
  }

  final percents = List<int>.filled(amounts.length, 0);
  final remainders = List<int>.filled(amounts.length, 0);
  var assigned = 0;
  for (var i = 0; i < amounts.length; i++) {
    final scaled = amounts[i].minorUnits * 100;
    percents[i] = scaled ~/ total;
    remainders[i] = scaled % total;
    assigned += percents[i];
  }

  // Порядок раздачи остатков: больший остаток раньше, при равенстве — выше в
  // списке. Недостающих единиц меньше, чем долей, поэтому индексы не выходят за
  // пределы.
  final order = List<int>.generate(amounts.length, (i) => i)
    ..sort((a, b) {
      if (remainders[a] != remainders[b]) {
        return remainders[b].compareTo(remainders[a]);
      }
      return a.compareTo(b);
    });
  for (var k = 0; k < 100 - assigned; k++) {
    percents[order[k]]++;
  }

  return [
    for (var i = 0; i < amounts.length; i++)
      PercentShare(
        percent: percents[i],
        isBelowOne: amounts[i].minorUnits > 0 && percents[i] == 0,
      ),
  ];
}

/// Сектора кольца по итогам категорий [totals] (уже отсортированным, как
/// даёт `totalsByCategory`: по убыванию суммы).
///
/// Правила (ADR 0007, п. 4):
/// - мелкая категория — доля меньше [smallSharePercent] %; сравнение
///   `сумма × 100 < итог × 3`, ровно 3 % мелкой не считается;
/// - мелкие объединяются в «Остальное», только если их две и больше; одна
///   мелкая остаётся своим сектором;
/// - именных секторов не больше [maxNamedSlices]; лишние (с конца списка)
///   тоже уходят в «Остальное».
///
/// Проценты считаются один раз для всего списка [totals] через
/// [percentShares]; процент «Остального» — сумма процентов входящих.
/// Порядок результата: именные сектора в порядке [totals], «Остальное» — в
/// конце. При нулевом итоге или пустом списке — пустой результат.
List<ChartSlice> chartSlices(List<CategoryTotal> totals) {
  if (totals.isEmpty) return const [];
  final shares = percentShares([for (final t in totals) t.amount]);
  var total = 0;
  for (final t in totals) {
    total += t.amount.minorUnits;
  }
  if (total == 0) return const [];

  bool isSmall(CategoryTotal t) =>
      t.amount.minorUnits * 100 < total * smallSharePercent;

  final smallCount = totals.where(isSmall).length;
  final groupSmall = smallCount >= 2;

  // Кандидаты на именные сектора в порядке списка, и группа «Остальное».
  final named = <int>[];
  final other = <int>[];
  for (var i = 0; i < totals.length; i++) {
    if (groupSmall && isSmall(totals[i])) {
      other.add(i);
    } else {
      named.add(i);
    }
  }
  if (named.length > maxNamedSlices) {
    other.addAll(named.sublist(maxNamedSlices));
    named.removeRange(maxNamedSlices, named.length);
    other.sort();
  }

  final slices = <ChartSlice>[
    for (final i in named)
      ChartSlice(
        categoryIds: [totals[i].categoryId],
        amount: totals[i].amount,
        share: shares[i],
        isOther: false,
      ),
  ];
  if (other.isNotEmpty) {
    final currency = totals.first.amount.currency;
    var amount = Money.zero(currency);
    var percent = 0;
    for (final i in other) {
      amount += totals[i].amount;
      percent += shares[i].percent ?? 0;
    }
    slices.add(
      ChartSlice(
        categoryIds: [for (final i in other) totals[i].categoryId],
        amount: amount,
        share: PercentShare(
          percent: percent,
          isBelowOne: amount.minorUnits > 0 && percent == 0,
        ),
        isOther: true,
      ),
    );
  }
  return slices;
}
