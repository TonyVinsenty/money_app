import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/domain/category_totals.dart';
import 'package:money_app/features/analytics/domain/comparison.dart';
import 'package:money_app/features/analytics/domain/operations_stats.dart';
import 'package:money_app/features/analytics/domain/period_comparison.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Не больше стольких подсказок показывается сразу.
const int maxAnalyticsHints = 3;

/// Правило 1: прошлое должно быть не меньше стольких целых единиц валюты.
const int _minPreviousWholeUnits = 1000;

/// Правило 2: минимум операций категории в каждом из двух периодов.
const int _minAverageOperations = 5;

/// Правило 2: минимальное изменение среднего чека, в процентах.
const int _minAverageChangePercent = 15;

/// Правило 3: минимальная доля дня недели в расходах, в процентах.
const int _minWeekdaySharePercent = 25;

/// Правило 3: минимум «дней данных» в окне.
const int _minDataDays = 28;

/// Подсказка на экране «Категории». Здесь только данные, без текста: тексты
/// собирает `presentation` (шаг a.17).
sealed class AnalyticsHint {
  const AnalyticsHint();
}

/// Правило 1: категория текущего периода уже больше, чем за весь прошлый.
final class CategoryAbovePreviousHint extends AnalyticsHint {
  const CategoryAbovePreviousHint({
    required this.categoryId,
    required this.current,
    required this.previousTotal,
  });

  final String categoryId;

  /// Расходы категории в текущем периоде (на сегодня).
  final Money current;

  /// Расходы категории за весь прошлый период (>= порога).
  final Money previousTotal;
}

/// Правило 2: средний чек категории заметно изменился.
final class AverageCheckChangeHint extends AnalyticsHint {
  const AverageCheckChangeHint({
    required this.categoryId,
    required this.currentAverage,
    required this.previousAverage,
    required this.percent,
  });

  final String categoryId;
  final Money currentAverage;
  final Money previousAverage;

  /// Изменение со знаком (+18 вырос, -20 снизился); по модулю >= 15.
  final int percent;
}

/// Правило 3: один день недели даёт >= 25 % расходов.
final class BusiestWeekdayHint extends AnalyticsHint {
  const BusiestWeekdayHint({
    required this.weekday,
    required this.sharePercent,
    required this.amount,
  });

  /// 1 - понедельник ... 7 - воскресенье (как `DateOnly.weekday`).
  final int weekday;

  /// Доля в расходах окна, целые проценты (округление «половина от нуля»).
  final int sharePercent;

  /// Расходы этого дня недели за всё окно.
  final Money amount;
}

/// Расходы по дням недели за [range]: список из 7 сумм, индекс 0 -
/// понедельник, 6 - воскресенье. Операция другой валюты - [ArgumentError].
List<Money> weekdayTotals(
  Iterable<Transaction> transactions,
  DateRange range, {
  required String currency,
}) {
  final totals = List<Money>.filled(7, Money.zero(currency));
  for (final transaction in transactions) {
    if (transaction.amount.currency != currency) {
      throw ArgumentError.value(
        transaction.amount.currency,
        'currency',
        'Expected $currency for every transaction',
      );
    }
    if (transaction.type != TransactionType.expense ||
        !range.contains(transaction.occurredOn)) {
      continue;
    }
    final index = transaction.occurredOn.weekday - 1;
    totals[index] = totals[index] + transaction.amount;
  }
  return totals;
}

/// До [maxAnalyticsHints] подсказок для [period]; считаются только расходы.
///
/// [transactions] - операции окна `dataWindow(period, today)` (или шире;
/// лишнее отсекается по датам). Порядок: правило 1, затем 2, затем 3; внутри
/// правила - по сумме категории «сейчас» по убыванию, ничья - по `categoryId`.
/// Результат не зависит от порядка входного списка. Если правил сработало
/// больше трёх, лишние (с конца) отбрасываются.
///
/// 1. Только если период содержит [today]. Категория в текущем периоде (на сегодня) больше (строго), чем за ВЕСЬ
///    прошлый период (`previousPeriod`, а для своего интервала - отрезок
///    перед ним), и прошлое >= 1 000 целых единиц валюты (порог в минорных
///    единицах: 1000 * 10^знаков). Прошлый период целиком всегда лежит в
///    `dataWindow`: окно начинается с начала предыдущего периода.
/// 2. Средний чек категории (`categoryStats`) изменился по модулю на >= 15 %
///    (`percentChange`, округлённый - как на экране) против `comparisonRange`;
///    операций категории >= 5 в каждом из двух периодов.
/// 3. Окно - `dataWindow`, обрезанное по [today]. «Дней данных» = число
///    календарных дней от первого расхода в окне до конца окна включительно;
///    нужно >= 28. День недели с долей >= 25 % (точно: сумма * 4 >= итог);
///    при равных суммах - более ранний день недели.
///
/// «Сейчас» в правилах 1 и 2 - операции периода по [today] включительно
/// (будущие не учитываются, чтобы «уже» было правдой). Правило 1 есть только
/// если период содержит [today]. [currency] - основная валюта из каталога.
List<AnalyticsHint> analyticsHints(
  Iterable<Transaction> transactions,
  AnalyticsPeriod period,
  DateOnly today, {
  required String currency,
}) {
  final all = transactions.toList();
  final periodRange = period.range;
  final includesToday = periodRange.contains(today);
  // Период целиком в будущем: «сейчас» пусто, правила 1 и 2 молчат.
  final current = periodRange.start > today
      ? null
      : DateRange(
          periodRange.start,
          periodRange.end < today ? periodRange.end : today,
        );
  final comparison = comparisonRange(period, today);
  final whole = previousPeriod(period)?.range ?? comparison;
  const expense = TransactionType.expense;

  final nowTotals = current == null
      ? const <CategoryTotal>[]
      : totalsByCategory(all, current, type: expense, currency: currency);
  final wholeTotals = {
    for (final t in totalsByCategory(
      all,
      whole,
      type: expense,
      currency: currency,
    ))
      t.categoryId: t.amount,
  };
  final digits = currencyInfoFor(currency).digits;
  var threshold = _minPreviousWholeUnits;
  for (var i = 0; i < digits; i++) {
    threshold *= 10;
  }

  final hints = <AnalyticsHint>[];

  // Правило 1 (nowTotals уже по сумме по убыванию, ничья - по id).
  // Только для периода с сегодняшним днём: «уже» про прошедший - неправда.
  for (final total in includesToday ? nowTotals : const <CategoryTotal>[]) {
    final before = wholeTotals[total.categoryId];
    if (before == null) continue;
    if (before.minorUnits >= threshold &&
        total.amount.minorUnits > before.minorUnits) {
      hints.add(
        CategoryAbovePreviousHint(
          categoryId: total.categoryId,
          current: total.amount,
          previousTotal: before,
        ),
      );
    }
  }

  // Правило 2.
  final nowStats = current == null
      ? const <CategoryStat>[]
      : categoryStats(all, current, expense, currency: currency);
  final beforeStats = {
    for (final s in categoryStats(all, comparison, expense, currency: currency))
      s.categoryId: s,
  };
  final changes = <AverageCheckChangeHint>[];
  for (final now in nowStats) {
    final before = beforeStats[now.categoryId];
    if (before == null ||
        now.count < _minAverageOperations ||
        before.count < _minAverageOperations) {
      continue;
    }
    final percent = percentChange(
      now.average.minorUnits,
      before.average.minorUnits,
    );
    if (percent != null && percent.abs() >= _minAverageChangePercent) {
      changes.add(
        AverageCheckChangeHint(
          categoryId: now.categoryId,
          currentAverage: now.average,
          previousAverage: before.average,
          percent: percent,
        ),
      );
    }
  }
  final nowAmounts = {for (final s in nowStats) s.categoryId: s.amount};
  changes.sort((a, b) {
    final byAmount = nowAmounts[b.categoryId]!.compareTo(
      nowAmounts[a.categoryId]!,
    );
    return byAmount != 0 ? byAmount : a.categoryId.compareTo(b.categoryId);
  });
  hints.addAll(changes);

  // Правило 3.
  final weekday = _busiestWeekday(all, period, today, currency);
  if (weekday != null) hints.add(weekday);

  return hints.length <= maxAnalyticsHints
      ? hints
      : hints.sublist(0, maxAnalyticsHints);
}

BusiestWeekdayHint? _busiestWeekday(
  List<Transaction> all,
  AnalyticsPeriod period,
  DateOnly today,
  String currency,
) {
  final window = dataWindow(period, today);
  final end = window.end < today ? window.end : today;
  if (end < window.start) return null;
  final range = DateRange(window.start, end);

  DateOnly? first;
  for (final t in all) {
    if (t.type != TransactionType.expense || !range.contains(t.occurredOn)) {
      continue;
    }
    if (first == null || t.occurredOn < first) first = t.occurredOn;
  }
  if (first == null) return null;
  if (DateRange(first, end).lengthInDays < _minDataDays) return null;

  final totals = weekdayTotals(all, range, currency: currency);
  var total = 0;
  var best = 0;
  for (var i = 0; i < 7; i++) {
    total += totals[i].minorUnits;
    if (totals[i].minorUnits > totals[best].minorUnits) best = i;
  }
  if (total == 0) return null;
  final top = totals[best].minorUnits;
  if (top * 100 < total * _minWeekdaySharePercent) return null;
  return BusiestWeekdayHint(
    weekday: best + 1,
    sharePercent: (top * 200 + total) ~/ (total * 2),
    amount: totals[best],
  );
}
