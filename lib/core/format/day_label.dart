import 'package:money_app/core/format/date_format.dart';
import 'package:money_app/core/time/date_only.dart';

/// Слова для сегодняшнего и вчерашнего дня. Живут в одном месте: их же
/// использует заголовок дня в «Истории» (`historyDayLabel` ниже).
const String todayLabel = 'Сегодня';
const String yesterdayLabel = 'Вчера';

/// Подпись дня [day] относительно [today]: «Сегодня», «Вчера» или дата
/// по-русски: в текущем году «19 сентября», в другом — «19 сентября 2025 г.».
///
/// Дата — через [formatDate], поэтому для неё нужен один раз выполненный
/// `initializeDateFormatting('ru')`; для «Сегодня» и «Вчера» он не нужен.
String dayLabel(DateOnly day, {required DateOnly today}) {
  if (day == today) return todayLabel;
  if (day == today.addDays(-1)) return yesterdayLabel;
  return day.year == today.year ? formatDayMonth(day) : formatDate(day);
}

/// Подпись дня в «Истории»: «Сегодня», «Вчера», для остальных дней текущего
/// года — «Пятница, 19 сентября» (без года), для прошлых и будущих лет — с
/// годом: «Пятница, 19 сентября 2025 г.» (с заглавной буквы). Год сравнивается с годом [today].
String historyDayLabel(DateOnly day, {required DateOnly today}) {
  if (day == today) return todayLabel;
  if (day == today.addDays(-1)) return yesterdayLabel;
  final text = day.year == today.year
      ? formatWeekdayDayMonth(day)
      : formatWeekdayFullDate(day);
  return '${text[0].toUpperCase()}${text.substring(1)}';
}
