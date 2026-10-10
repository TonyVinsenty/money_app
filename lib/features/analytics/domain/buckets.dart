import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Длиннее этого (в днях) свой интервал рисуется по месяцам, а не по дням.
const int maxDailyBucketDays = 62;

/// Одна корзина столбчатого графика: отрезок дней и сумма за него.
final class Bucket {
  const Bucket({required this.range, required this.amount});

  /// Дни корзины включительно (для месяца — обрезаны границами периода).
  final DateRange range;

  /// Сумма операций корзины; у пустой корзины — ноль.
  final Money amount;
}

/// Как делить [period] на корзины (ADR 0012, п. 4).
enum BucketStep { day, month, none }

/// Шаг корзины: неделя, месяц и свой интервал до 62 дней — день; год и свой
/// интервал длиннее 62 дней — месяц; день — корзин нет.
BucketStep bucketStepFor(AnalyticsPeriod period) => switch (period.kind) {
  PeriodKind.day => BucketStep.none,
  PeriodKind.week || PeriodKind.month => BucketStep.day,
  PeriodKind.year => BucketStep.month,
  PeriodKind.custom =>
    period.range.lengthInDays <= maxDailyBucketDays
        ? BucketStep.day
        : BucketStep.month,
};

/// Суммы операций вида [type] по корзинам [period], включая нулевые.
///
/// Если задан [categoryId], считаются операции этой категории вместе с её
/// подкатегориями (у такой операции `categoryId` — родитель). Корзины идут
/// по порядку, покрывают период целиком без пропусков. Для вида «День» —
/// пустой список. Операция другой валюты (даже вне периода) — [ArgumentError].
List<Bucket> bucketTotals(
  Iterable<Transaction> transactions,
  AnalyticsPeriod period, {
  required TransactionType type,
  required String currency,
  String? categoryId,
}) {
  final step = bucketStepFor(period);
  final ranges = switch (step) {
    BucketStep.none => <DateRange>[],
    BucketStep.day => [
      for (var d = period.range.start; d <= period.range.end; d = d.addDays(1))
        DateRange(d, d),
    ],
    BucketStep.month => _monthRanges(period.range),
  };
  final sums = List<Money>.filled(ranges.length, Money.zero(currency));
  for (final t in transactions) {
    if (t.amount.currency != currency) {
      throw ArgumentError.value(
        t.amount.currency,
        'currency',
        'Expected $currency for every transaction',
      );
    }
    if (t.type != type) continue;
    if (categoryId != null && t.categoryId != categoryId) continue;
    if (!period.range.contains(t.occurredOn)) continue;
    final index = ranges.indexWhere((r) => r.contains(t.occurredOn));
    if (index >= 0) sums[index] += t.amount;
  }
  return [
    for (var i = 0; i < ranges.length; i++)
      Bucket(range: ranges[i], amount: sums[i]),
  ];
}

/// Календарные месяцы, пересекающие [range]; крайние обрезаны его границами.
List<DateRange> _monthRanges(DateRange range) {
  final result = <DateRange>[];
  var cursor = range.start;
  while (cursor <= range.end) {
    final month = monthRange(cursor);
    final end = month.end < range.end ? month.end : range.end;
    result.add(DateRange(cursor, end));
    cursor = month.end.addDays(1);
  }
  return result;
}

/// Среднее по корзинам: сумма / число корзин, округление «половина от нуля».
///
/// Считаются только корзины, начавшиеся не позже [today]: у текущего периода
/// будущие нули не разбавляют среднее (у прошедшего периода это все корзины).
/// Нет ни одной такой корзины — `null`.
Money? bucketAverage(List<Bucket> buckets, DateOnly today) {
  final elapsed = [
    for (final b in buckets)
      if (b.range.start <= today) b,
  ];
  if (elapsed.isEmpty) return null;
  var total = Money.zero(elapsed.first.amount.currency);
  for (final b in elapsed) {
    total += b.amount;
  }
  return total.dividedBy(elapsed.length);
}
