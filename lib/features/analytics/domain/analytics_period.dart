import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';

/// Период экрана «Аналитика»: вид (день, неделя, месяц, год или свой
/// интервал) и его границы (ADR 0007, п. 6).
final class AnalyticsPeriod {
  const AnalyticsPeriod(this.kind, this.range);

  final PeriodKind kind;

  /// Границы включительно: первый и последний день.
  final DateRange range;

  @override
  bool operator ==(Object other) =>
      other is AnalyticsPeriod && other.kind == kind && other.range == range;

  @override
  int get hashCode => Object.hash(kind, range);

  @override
  String toString() => '$kind $range';
}

/// Период вида [kind], в который входит [today] (это «текущий» период).
///
/// «Сегодня» передаётся явно: сам код не читает часы. Экран берёт дату из
/// `Clock.today()`, а тесты подставляют фиксированный день. Для
/// [PeriodKind.custom] текущего периода нет, его задают границами через
/// [customPeriod], поэтому такой вид — [ArgumentError].
AnalyticsPeriod currentPeriod(PeriodKind kind, DateOnly today) {
  final range = switch (kind) {
    PeriodKind.day => dayRange(today),
    PeriodKind.week => weekRange(today),
    PeriodKind.month => monthRange(today),
    PeriodKind.year => yearRange(today),
    PeriodKind.custom => throw ArgumentError.value(
      kind,
      'kind',
      'custom period has no current value: use customPeriod',
    ),
  };
  return AnalyticsPeriod(kind, range);
}

/// Свой интервал от [start] до [end] включительно.
///
/// [end] раньше [start] — [ArgumentError] (бросает сам `DateRange`). Конец
/// позже [today] — тоже [ArgumentError]: будущих операций не бывает
/// (ADR 0004).
AnalyticsPeriod customPeriod(
  DateOnly start,
  DateOnly end, {
  required DateOnly today,
}) {
  final range = DateRange(start, end);
  if (end > today) {
    throw ArgumentError.value(end, 'end', 'must not be after today ($today)');
  }
  return AnalyticsPeriod(PeriodKind.custom, range);
}

/// Предыдущий период того же вида. Для свободного интервала — `null`:
/// у него стрелок нет, он не сдвигается.
///
/// Берём день перед началом текущего периода и находим период, в который он
/// входит. Так переход через январь (1.01 → 31.12) и через високосный
/// февраль выходит сам собой.
AnalyticsPeriod? previousPeriod(AnalyticsPeriod period) {
  if (period.kind == PeriodKind.custom) return null;
  return currentPeriod(period.kind, period.range.start.addDays(-1));
}

/// Следующий период того же вида, но не позже периода, содержащего
/// [today]. Если следующий начинается после [today], возвращается `null`:
/// вперёд дальше текущего периода не ходим. Для свободного интервала тоже
/// `null`.
AnalyticsPeriod? nextPeriod(AnalyticsPeriod period, DateOnly today) {
  if (period.kind == PeriodKind.custom) return null;
  final next = currentPeriod(period.kind, period.range.end.addDays(1));
  return next.range.start > today ? null : next;
}

/// Можно ли сдвинуться вперёд (стрелка «вперёд» активна).
bool canGoForward(AnalyticsPeriod period, DateOnly today) =>
    nextPeriod(period, today) != null;

/// Смена вида периода: новый период того же вида, который содержит
/// «опорный» день. Опорный день — последний день текущего периода, но не
/// позже [today], чтобы не уйти в будущее.
///
/// Примеры при сегодня 04.10.2026: неделя 28.09-04.10 → октябрь;
/// неделя 21.09-27.09 → сентябрь; день 15.09 → неделя 14.09-20.09.
///
/// Переключиться на свой интервал этой функцией нельзя: нужны границы,
/// их задаёт [customPeriod] — иначе [ArgumentError].
AnalyticsPeriod switchKind(
  AnalyticsPeriod current,
  PeriodKind kind,
  DateOnly today,
) {
  if (kind == PeriodKind.custom) {
    throw ArgumentError.value(
      kind,
      'kind',
      'switching to a custom period needs bounds: use customPeriod',
    );
  }
  final anchor = current.range.end < today ? current.range.end : today;
  return currentPeriod(kind, anchor);
}
