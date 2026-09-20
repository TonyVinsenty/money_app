import 'package:money_app/core/format/date_format.dart';
import 'package:money_app/core/time/date_only.dart';

/// Слова для сегодняшнего и вчерашнего дня. Живут в одном месте: их же будет
/// использовать заголовок дня в «Истории» (шаг 2.27).
const String todayLabel = 'Сегодня';
const String yesterdayLabel = 'Вчера';

/// Подпись дня [day] относительно [today]: «Сегодня», «Вчера» или полная дата
/// по-русски («19 сентября 2026 г.»).
///
/// Дата — через [formatDate], поэтому для неё нужен один раз выполненный
/// `initializeDateFormatting('ru')`; для «Сегодня» и «Вчера» он не нужен.
String dayLabel(DateOnly day, {required DateOnly today}) {
  if (day == today) return todayLabel;
  if (day == today.addDays(-1)) return yesterdayLabel;
  return formatDate(day);
}
