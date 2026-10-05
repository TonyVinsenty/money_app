import 'package:intl/intl.dart';
import 'package:money_app/core/time/date_only.dart';

/// Полная дата по-русски, например «19 сентября 2026 г.».
///
/// Перед первым вызовом нужно один раз выполнить
/// `initializeDateFormatting('ru')` (обычно в `main`), иначе `intl` бросит
/// `LocaleDataException`: данные русской локали не загружены.
String formatDate(DateOnly date) =>
    DateFormat.yMMMMd('ru').format(date.toDateTime());

/// День недели, число и месяц без года: «пятница, 19 сентября». Требует
/// `initializeDateFormatting('ru')`.
String formatWeekdayDayMonth(DateOnly date) =>
    DateFormat('EEEE, d MMMM', 'ru').format(date.toDateTime());

/// То же с годом: «пятница, 19 сентября 2025 г.». Требует
/// `initializeDateFormatting('ru')`.
String formatWeekdayFullDate(DateOnly date) =>
    DateFormat.yMMMMEEEEd('ru').format(date.toDateTime());

/// Число и месяц без года и дня недели: «30 сентября». Требует
/// `initializeDateFormatting('ru')`.
String formatDayMonth(DateOnly date) =>
    DateFormat('d MMMM', 'ru').format(date.toDateTime());

/// Месяц и год по-русски, например «сентябрь 2026 г.» (месяц в именительном
/// падеже). Требует того же `initializeDateFormatting('ru')`, что и
/// [formatDate].
String formatMonthYear(DateOnly date) =>
    DateFormat.yMMMM('ru').format(date.toDateTime());

/// Название месяца по-русски в именительном падеже и с маленькой буквы:
/// «сентябрь». Формат `LLLL` (отдельно стоящий месяц) даёт «сентябрь», а
/// `MMMM` — «сентября». Требует `initializeDateFormatting('ru')`.
String formatMonthName(DateOnly date) =>
    DateFormat.LLLL('ru').format(date.toDateTime());

/// Подпись переключателя месяца: «Сентябрь 2026» (с большой буквы, без «г.»).
/// Требует `initializeDateFormatting('ru')`.
String formatMonthTitle(DateOnly date) {
  final name = formatMonthName(date);
  return '${name[0].toUpperCase()}${name.substring(1)} ${date.year}';
}
