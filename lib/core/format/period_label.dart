import 'package:money_app/core/format/date_format.dart';
import 'package:money_app/core/format/day_label.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';

/// Подпись периода для экрана «Аналитика» и экрана категории, по-русски, в
/// стиле «Главной» (с заглавной буквы, без «г.»):
/// - день: «Сегодня», «Вчера», «Пятница, 2 октября»; день не этого года
///   (год [today]) — «2 октября 2025»;
/// - неделя: «5\u201311 октября», «28 сентября \u2013 4 октября», через Новый
///   год — «29 декабря 2025 \u2013 4 января 2026»; неделя не этого года — год в
///   конце: «24\u201330 ноября 2025»;
/// - месяц: «Октябрь 2026»;
/// - год: «2026»;
/// - свой интервал — всегда с годом: «1\u201315 сентября 2026», один день —
///   «15 сентября 2026».
///
/// Тире — короткое (\u2013): без пробелов внутри одного месяца, с пробелами
/// между разными месяцами.
///
/// Требует один раз выполненного `initializeDateFormatting('ru')`.
String formatPeriodLabel(
  PeriodKind kind,
  DateRange range, {
  required DateOnly today,
}) {
  return switch (kind) {
    PeriodKind.day => _dayLabel(range.start, today),
    PeriodKind.week => _rangeLabel(
      range,
      withYear: range.start.year != today.year || range.end.year != today.year,
    ),
    PeriodKind.month => formatMonthTitle(range.start),
    PeriodKind.year => '${range.start.year}',
    PeriodKind.custom => _rangeLabel(range, withYear: true),
  };
}

String _dayLabel(DateOnly day, DateOnly today) {
  if (day.year != today.year) return '${formatDayMonth(day)} ${day.year}';
  if (day == today) return todayLabel;
  if (day == today.addDays(-1)) return yesterdayLabel;
  final text = formatWeekdayDayMonth(day);
  return '${text[0].toUpperCase()}${text.substring(1)}';
}

/// Интервал дней. Год: если [withYear] и годы концов разные — у обоих концов,
/// иначе один раз в конце.
String _rangeLabel(DateRange range, {required bool withYear}) {
  final start = range.start;
  final end = range.end;
  if (start == end) {
    return withYear
        ? '${formatDayMonth(start)} ${start.year}'
        : formatDayMonth(start);
  }
  if (start.year != end.year) {
    return '${formatDayMonth(start)} ${start.year} \u2013 '
        '${formatDayMonth(end)} ${end.year}';
  }
  final year = withYear ? ' ${end.year}' : '';
  if (start.month == end.month) {
    return '${start.day}\u2013${formatDayMonth(end)}$year';
  }
  return '${formatDayMonth(start)} \u2013 ${formatDayMonth(end)}$year';
}
