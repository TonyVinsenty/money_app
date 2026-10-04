import 'package:intl/intl.dart';
import 'package:money_app/core/time/period.dart';

/// Подпись периода для заголовка экрана, по-русски:
/// - день: «4 октября 2026»;
/// - неделя: «неделя 28.09\u201304.10» (если неделя через Новый год, годы
///   пишутся у обеих дат: «неделя 29.12.2025\u201304.01.2026»);
/// - месяц: «октябрь 2026»;
/// - год: «2026 год»;
/// - свой интервал: «с 01.09.2026 по 04.10.2026».
///
/// Требует один раз выполненного `initializeDateFormatting('ru')`, как и
/// остальные функции этого каталога.
String formatPeriodLabel(PeriodKind kind, DateRange range) {
  return switch (kind) {
    PeriodKind.day => DateFormat(
      'd MMMM y',
      'ru',
    ).format(range.start.toDateTime()),
    PeriodKind.week => _weekLabel(range),
    PeriodKind.month => DateFormat(
      'LLLL y',
      'ru',
    ).format(range.start.toDateTime()),
    PeriodKind.year => '${range.start.year} год',
    PeriodKind.custom =>
      'с ${DateFormat('dd.MM.yyyy').format(range.start.toDateTime())} '
          'по ${DateFormat('dd.MM.yyyy').format(range.end.toDateTime())}',
  };
}

String _weekLabel(DateRange range) {
  // Год в датах нужен, только если неделя переходит через Новый год.
  final pattern = range.start.year == range.end.year ? 'dd.MM' : 'dd.MM.yyyy';
  final from = DateFormat(pattern).format(range.start.toDateTime());
  final to = DateFormat(pattern).format(range.end.toDateTime());
  return 'неделя $from\u2013$to';
}
