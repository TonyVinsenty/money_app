import 'package:money_app/core/format/date_format.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/format/percent_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/period_comparison.dart';
import 'package:money_app/features/analytics/presentation/analytics_controller.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Тексты вкладки «Аналитика», добавленные этапом А (ADR 0012). Тексты
/// утверждены пользователем 2026-10-11 (ROADMAP, «Тексты» Т1\u2013Т6).
///
/// Особые символы собраны из кодов, а не набраны (правило проекта для
/// невидимых и похожих на обычные знаков).
final String _nbsp = String.fromCharCode(0x00A0);
final String _minus = String.fromCharCode(0x2212);
final String _dash = String.fromCharCode(0x2013);

/// Т1. Название раздела в строке разделов.
String analyticsSectionTitle(AnalyticsSection section) => switch (section) {
  AnalyticsSection.categories => 'Категории',
  AnalyticsSection.dynamics => 'Динамика',
  AnalyticsSection.comparison => 'Сравнение',
  AnalyticsSection.operations => 'Операции',
};

/// Месяцы в предложном падеже («в августе»).
const List<String> _monthsPrepositional = [
  'январе',
  'феврале',
  'марте',
  'апреле',
  'мае',
  'июне',
  'июле',
  'августе',
  'сентябре',
  'октябре',
  'ноябре',
  'декабре',
];

/// Т2. С чем сравниваем, так, чтобы вставить после «чем» и «сколько»:
/// «1\u201311 сентября», «в августе», «вчера», «в 2025 году». Год пишется,
/// только если он не тот же, что у [today]. Требует
/// `initializeDateFormatting('ru')`.
String comparisonPhrase(DateRange range, DateOnly today) {
  final start = range.start;
  final end = range.end;
  final yearSuffix = start.year == today.year && end.year == today.year
      ? ''
      : ' ${end.year}';

  if (start == end) {
    if (start == today.addDays(-1)) return 'вчера';
    return '${formatDayMonth(start)}${start.year == today.year ? '' : ' ${start.year}'}';
  }
  if (range == monthRange(start)) {
    return 'в ${_monthsPrepositional[start.month - 1]}$yearSuffix';
  }
  if (range == yearRange(start)) return 'в ${start.year} году';
  if (start.year != end.year) {
    return '${formatDayMonth(start)} ${start.year} $_dash '
        '${formatDayMonth(end)} ${end.year}';
  }
  if (start.month == end.month) {
    return '${start.day}$_dash${formatDayMonth(end)}$yearSuffix';
  }
  return '${formatDayMonth(start)} $_dash ${formatDayMonth(end)}$yearSuffix';
}

/// Т2. Заголовок итога: «Расходы: 48 200,00 ₽».
String comparisonTotalTitle(TransactionType type, Money total) =>
    '${type == TransactionType.expense ? 'Расходы' : 'Доходы'}: '
    '${formatMoney(total)}';

/// Т2. Процент со знаком: «+12 %», «\u22124 %», «0 %».
String signedPercent(int percent) {
  final sign = percent > 0
      ? '+'
      : percent < 0
      ? _minus
      : '';
  return '$sign${percent.abs()}$_nbsp%';
}

/// Т2. Процент со знаком для скринридера: «плюс 40 процентов».
String spokenSignedPercent(int percent) {
  final words = pluralRu(percent.abs(), 'процент', 'процента', 'процентов');
  final sign = percent > 0
      ? 'плюс '
      : percent < 0
      ? 'минус '
      : '';
  return '$sign${percent.abs()} $words';
}

/// Т2. Строка под итогом: на сколько больше или меньше, чем [phrase]
/// ([comparisonPhrase]). Раньше было 0 — «1\u201311 сентября расходов не было».
/// Для скринридера ([spoken]) суммы и проценты читаются словами.
String comparisonSummaryText(
  AmountChange change,
  TransactionType type,
  String phrase, {
  bool spoken = false,
}) {
  if (change.previous.isZero) {
    final what = type == TransactionType.expense ? 'расходов' : 'доходов';
    return '${_capitalize(phrase)} $what не было';
  }
  final difference = change.difference;
  if (difference.isZero) return 'столько же, сколько $phrase';
  final more = !difference.isNegative;
  final amount = more ? difference : -difference;
  final percent = change.percent!;
  final money = spoken ? spokenMoney(amount) : formatMoney(amount);
  final percentText = spoken
      ? spokenSignedPercent(percent)
      : '(${signedPercent(percent)})';
  final word = more ? 'больше' : 'меньше';
  return spoken
      ? 'на $money $word, $percentText, чем $phrase'
      : 'на $money $word $percentText, чем $phrase';
}

String _capitalize(String text) =>
    text.isEmpty ? text : '${text[0].toUpperCase()}${text.substring(1)}';

/// Т2. Первая строка категории: «Кафе · 8 000,00 ₽»; исчезнувшая —
/// «Кафе · 0,00 ₽ · было 3 000,00 ₽».
String comparisonRowTitle(String name, AmountChange change) {
  final now = formatMoney(change.current);
  if (change.current.isZero && !change.previous.isZero) {
    return '$name · $now · было ${formatMoney(change.previous)}';
  }
  return '$name · $now';
}

/// Т2. Вторая строка категории: «↑ на 2 300,00 ₽ (+40 %)»,
/// «↓ на 500,00 ₽ (\u22126 %)», «= столько же»; новая — «раньше не было».
String comparisonRowDelta(AmountChange change) {
  if (change.previous.isZero) return 'раньше не было';
  final difference = change.difference;
  if (difference.isZero) return '= столько же';
  final more = !difference.isNegative;
  final amount = formatMoney(more ? difference : -difference);
  final arrow = more ? '↑' : '↓';
  return '$arrow на $amount (${signedPercent(change.percent!)})';
}

/// Т2. Озвучка строки категории: «Кафе, 8000 рублей, больше на 2300 рублей,
/// плюс 40 процентов».
String comparisonRowSpoken(String name, AmountChange change) {
  final now = spokenMoney(change.current);
  if (change.previous.isZero) return '$name, $now, раньше не было';
  final difference = change.difference;
  final was = change.current.isZero
      ? ', было ${spokenMoney(change.previous)}'
      : '';
  if (difference.isZero) return '$name, $now$was, столько же';
  final more = !difference.isNegative;
  final amount = spokenMoney(more ? difference : -difference);
  return '$name, $now$was, ${more ? 'больше' : 'меньше'} на $amount, '
      '${spokenSignedPercent(change.percent!)}';
}

/// Т2. Когда в выбранном типе нет ничего ни сейчас, ни в сравнении.
String comparisonNothingText(TransactionType type) =>
    type == TransactionType.expense
    ? 'За этот период расходов нет'
    : 'За этот период доходов нет';
