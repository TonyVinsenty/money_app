import 'package:intl/intl.dart';
import 'package:money_app/core/time/date_only.dart';

/// Полная дата по-русски, например «19 сентября 2026 г.».
///
/// Перед первым вызовом нужно один раз выполнить
/// `initializeDateFormatting('ru')` (обычно в `main`), иначе `intl` бросит
/// `LocaleDataException`: данные русской локали не загружены.
String formatDate(DateOnly date) =>
    DateFormat.yMMMMd('ru').format(date.toDateTime());

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
