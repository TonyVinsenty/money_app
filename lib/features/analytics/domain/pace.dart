import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// С какого числа месяца показываем прогноз (ADR 0012, вопрос 4): раньше
/// оценка слишком грубая (аренда 1-го числа раздувает её).
const int forecastFromDay = 7;

/// Темп и прогноз расходов текущего месяца.
final class MonthForecast {
  const MonthForecast({
    required this.spent,
    required this.averagePerDay,
    required this.forecast,
    required this.daysPassed,
    required this.daysInMonth,
  });

  /// Потрачено с 1-го числа по сегодня включительно (без будущих операций).
  final Money spent;

  /// Потрачено / дней от первой операции месяца по сегодня (округление
  /// «половина от нуля»); то же число, что «В среднем … в день» в «Динамике».
  final Money averagePerDay;

  /// Оценка на весь месяц: потрачено + среднее × оставшиеся дни, но не меньше
  /// итога месяца со всеми (в том числе будущими) операциями.
  final Money forecast;

  /// Сколько дней прошло с 1-го числа, включая сегодня (7..31).
  final int daysPassed;

  /// Всего дней в месяце (28..31).
  final int daysInMonth;
}

/// Прогноз к концу месяца по линейному темпу «если тратить так же».
///
/// Возвращает `null`, если [period] — не текущий месяц (вид не `month` или не
/// содержит [today]), [today] раньше [forecastFromDay]-го числа (порог по
/// календарю) или по сегодня ничего не потрачено (прогнозировать нечего).
///
/// Считаются операции вида [type]; [categoryId] (если задан) сужает до
/// категории вместе с её подкатегориями. Среднее в день = потрачено по сегодня
/// / дней от первой (ненулевой) операции месяца по сегодня, как
/// `bucketAverage` в «Динамике» (иначе строки на экране противоречили бы друг
/// другу). Прогноз = потрачено + среднее × дней после сегодняшнего до конца
/// месяца. Операции с будущей датой в среднее не входят, но прогноз не бывает
/// меньше итога месяца со всеми операциями: `max(прогноз, итог месяца)`.
///
/// Валюта каждой операции проверяется (даже вне периода): другая валюта —
/// [ArgumentError], как в `totalsByCategory`.
MonthForecast? monthForecast(
  Iterable<Transaction> transactions,
  AnalyticsPeriod period,
  TransactionType type,
  DateOnly today, {
  required String currency,
  String? categoryId,
}) {
  var spent = Money.zero(currency);
  var monthTotal = Money.zero(currency);
  DateOnly? firstDay;
  for (final transaction in transactions) {
    if (transaction.amount.currency != currency) {
      throw ArgumentError.value(
        transaction.amount.currency,
        'currency',
        'Expected $currency for every transaction',
      );
    }
    if (transaction.type != type) continue;
    if (categoryId != null && transaction.categoryId != categoryId) continue;
    final day = transaction.occurredOn;
    if (!period.range.contains(day)) continue;
    monthTotal += transaction.amount;
    if (day > today) continue;
    spent += transaction.amount;
    if (!transaction.amount.isZero && (firstDay == null || day < firstDay)) {
      firstDay = day;
    }
  }

  if (period.kind != PeriodKind.month || !period.range.contains(today)) {
    return null;
  }
  if (today.day < forecastFromDay) return null;

  if (spent.isZero || firstDay == null) return null;

  final daysInMonth = period.range.lengthInDays;
  final daysActive = today.day - firstDay.day + 1;
  final average = spent.dividedBy(daysActive);
  final remaining = daysInMonth - today.day;
  final projected =
      BigInt.from(spent.minorUnits) +
      BigInt.from(average.minorUnits) * BigInt.from(remaining);
  final forecast = _clamped(projected, currency);
  return MonthForecast(
    spent: spent,
    averagePerDay: average,
    forecast: forecast > monthTotal ? forecast : monthTotal,
    daysPassed: today.day,
    daysInMonth: daysInMonth,
  );
}

/// Результат расчёта в `BigInt` (он не «заворачивается»), не влезающий в
/// `int`, ограничивается его границей.
Money _clamped(BigInt value, String currency) {
  final max = BigInt.from(0x7FFFFFFFFFFFFFFF);
  final clamped = value > max ? max : value;
  return Money.fromMinor(clamped.toInt(), currency);
}
