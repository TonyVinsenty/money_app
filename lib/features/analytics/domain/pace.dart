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

  /// Потрачено с 1-го числа по сегодня включительно.
  final Money spent;

  /// Потрачено / прошло дней (с 1-го числа, округление «половина от нуля»).
  final Money averagePerDay;

  /// Оценка на весь месяц: потрачено × дней в месяце / прошло дней.
  final Money forecast;

  /// Сколько дней прошло, включая сегодня (7..31).
  final int daysPassed;

  /// Всего дней в месяце (28..31).
  final int daysInMonth;
}

/// Прогноз к концу месяца по линейному темпу «если тратить так же».
///
/// Возвращает `null`, если [period] — не текущий месяц (вид не `month` или не
/// содержит [today]) либо [today] раньше [forecastFromDay]-го числа.
///
/// Считаются операции вида [type] за период с 1-го числа по [today]
/// включительно; [categoryId] (если задан) сужает до категории вместе с её
/// подкатегориями. Операции с будущей датой в этом месяце НЕ считаются:
/// прогноз опирается на уже прошедшие дни. Делим на прошедшие дни месяца с
/// 1-го числа, а не с первой операции: это темп месяца, поэтому он может
/// отличаться от «В среднем … в день» в «Динамике» (там — с первой корзины
/// с операциями, ADR 0012, п. 4).
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
    if (!period.range.contains(day) || day > today) continue;
    spent += transaction.amount;
  }

  if (period.kind != PeriodKind.month || !period.range.contains(today)) {
    return null;
  }
  if (today.day < forecastFromDay) return null;

  final daysPassed = today.day;
  final daysInMonth = period.range.lengthInDays;
  return MonthForecast(
    spent: spent,
    averagePerDay: spent.dividedBy(daysPassed),
    forecast: _scaled(spent, daysInMonth, daysPassed),
    daysPassed: daysPassed,
    daysInMonth: daysInMonth,
  );
}

/// `amount × numerator / denominator` с округлением «половина от нуля».
/// Промежуточное произведение считается в `BigInt`, поэтому оно не
/// «заворачивается» (у `Money * int` проверки переполнения нет). Результат,
/// не влезающий в `int`, ограничивается его границей.
Money _scaled(Money amount, int numerator, int denominator) {
  final product = BigInt.from(amount.minorUnits) * BigInt.from(numerator);
  final divisor = BigInt.from(denominator);
  final half = divisor ~/ BigInt.two;
  final shifted = product.isNegative ? product - half : product + half;
  final result = shifted ~/ divisor; // ~/ у BigInt тоже к нулю
  final max = BigInt.from(0x7FFFFFFFFFFFFFFF);
  final clamped = result > max ? max : (result < -max ? -max : result);
  return Money.fromMinor(clamped.toInt(), amount.currency);
}
