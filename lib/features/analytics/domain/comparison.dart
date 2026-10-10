import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';

/// Период, с которым сравнивается [period] (ADR 0012, п. 3).
///
/// - Прошедший период (закончился до [today]) сравнивается с целым
///   предыдущим периодом того же вида.
/// - Текущий, ещё не закончившийся — с тем же отрезком от начала
///   предыдущего: 1-11 октября против 1-11 сентября. Нет такого дня в
///   прошлом месяце (31 октября -> сентябрь) — берётся его последний день;
///   для года сравнивается та же календарная дата (29 февраля -> 28 февраля).
/// - Текущий день сравнивается с целым вчерашним днём.
/// - Свой интервал — с отрезком той же длины сразу перед ним.
///
/// «Сегодня» передаётся явно, часы здесь не читаются.
DateRange comparisonRange(AnalyticsPeriod period, DateOnly today) {
  final range = period.range;
  if (period.kind == PeriodKind.custom) {
    final length = range.lengthInDays;
    return DateRange(range.start.addDays(-length), range.start.addDays(-1));
  }
  final whole = previousPeriod(period)!.range;
  if (!range.contains(today)) return whole;

  final DateOnly end;
  if (period.kind == PeriodKind.year) {
    final lastDay = monthRange(DateOnly(whole.start.year, today.month, 1)).end;
    end = DateOnly(
      whole.start.year,
      today.month,
      today.day < lastDay.day ? today.day : lastDay.day,
    );
  } else {
    final elapsed = DateRange(range.start, today).lengthInDays;
    final shifted = whole.start.addDays(elapsed - 1);
    end = shifted < whole.end ? shifted : whole.end;
  }
  return DateRange(whole.start, end);
}

/// Окно данных вкладки: от начала периода сравнения до конца периода
/// (ADR 0012, п. 2).
DateRange dataWindow(AnalyticsPeriod period, DateOnly today) =>
    DateRange(comparisonRange(period, today).start, period.range.end);
