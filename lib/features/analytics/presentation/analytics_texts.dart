import 'package:intl/intl.dart';
import 'package:money_app/core/format/date_format.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/format/percent_format.dart';
import 'package:money_app/core/format/period_label.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/domain/buckets.dart';
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
String comparisonTotalTitle(
  TransactionType type,
  Money total, {
  bool spoken = false,
}) =>
    '${type == TransactionType.expense ? 'Расходы' : 'Доходы'}: '
    '${spoken ? spokenMoney(total) : formatMoney(total)}';

final NumberFormat _percentFormat = NumberFormat.decimalPattern('ru');

/// Т2. Процент со знаком: «+12 %», «\u22124 %», «0 %».
String signedPercent(int percent, {bool isBelowOne = false}) {
  // Разница есть, но процент округлился до 0: «<1 %» без знака, направление
  // уже сказано словами «больше»/«меньше».
  if (isBelowOne) return '<1$_nbsp%';
  final sign = percent > 0
      ? '+'
      : percent < 0
      ? _minus
      : '';
  return '$sign${_percentFormat.format(percent.abs())}$_nbsp%';
}

/// Т2. Процент со знаком для скринридера: «плюс 40 процентов».
String spokenSignedPercent(int percent, {bool isBelowOne = false}) {
  if (isBelowOne) return 'меньше 1 процента';
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
      ? spokenSignedPercent(percent, isBelowOne: percent == 0)
      : '(${signedPercent(percent, isBelowOne: percent == 0)})';
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
  final percent = change.percent!;
  return '$arrow на $amount (${signedPercent(percent, isBelowOne: percent == 0)})';
}

/// Т2. Озвучка строки категории: «Кафе, 8000 рублей, больше на 2300 рублей,
/// плюс 40 процентов».
String comparisonRowSpoken(String name, AmountChange change) {
  final now = spokenMoney(change.current);
  if (change.previous.isZero) return '$name, $now, раньше не было';
  final difference = change.difference;
  final percent = change.percent!;
  final percentText = spokenSignedPercent(percent, isBelowOne: percent == 0);
  if (change.current.isZero) {
    // Исчезнувшая категория: разница равна прежней сумме, не повторяем её.
    return '$name, $now, раньше было ${spokenMoney(change.previous)}, '
        '$percentText';
  }
  if (difference.isZero) return '$name, $now, столько же';
  final more = !difference.isNegative;
  final amount = spokenMoney(more ? difference : -difference);
  return '$name, $now, ${more ? 'больше' : 'меньше'} на $amount, '
      '$percentText';
}

/// Т2. Когда в выбранном типе нет ничего ни сейчас, ни в сравнении.
String comparisonNothingText(TransactionType type) =>
    type == TransactionType.expense
    ? 'За этот период расходов нет'
    : 'За этот период доходов нет';

/// Т3. Заголовок «Динамики»: «Расходы по дням», «Доходы по месяцам».
String dynamicsTitle(TransactionType type, BucketStep step) =>
    '${type == TransactionType.expense ? 'Расходы' : 'Доходы'} '
    '${step == BucketStep.month ? 'по месяцам' : 'по дням'}';

/// Т3. Под графиком: «В среднем 2 400,00 ₽ в день» («в месяц»). Для
/// скринридера ([spoken]) сумма словами.
String dynamicsAverageText(
  Money average,
  BucketStep step, {
  bool spoken = false,
}) =>
    'В среднем ${spoken ? spokenMoney(average) : formatMoney(average)} '
    '${step == BucketStep.month ? 'в месяц' : 'в день'}';

/// Т3. Название корзины: «12 октября» (год добавляется, если он не тот же, что
/// у [today]) или «Октябрь 2026» для месячной.
String dynamicsBucketLabel(Bucket bucket, BucketStep step, DateOnly today) {
  final start = bucket.range.start;
  if (step == BucketStep.month) return formatMonthTitle(start);
  return start.year == today.year
      ? formatDayMonth(start)
      : '${formatDayMonth(start)} ${start.year}';
}

/// Т3. Значение выбранного столбика: «12 октября: 5 400,00 ₽».
String dynamicsSelectedText(Bucket bucket, BucketStep step, DateOnly today) =>
    '${dynamicsBucketLabel(bucket, step, today)}: ${formatMoney(bucket.amount)}';

/// Т3. Пояснение вместо графика для вида «День».
const String dynamicsDayHint =
    'Выберите неделю, месяц, год или свой период — здесь появятся '
    'столбики по дням';

/// Т3. Название свёрнутого списка: «По дням» / «По месяцам».
String dynamicsListTitle(BucketStep step) =>
    step == BucketStep.month ? 'По месяцам' : 'По дням';

/// Т3. Строка списка для скринридера: «12 октября, 5400 рублей».
String dynamicsRowSpoken(Bucket bucket, BucketStep step, DateOnly today) =>
    '${dynamicsBucketLabel(bucket, step, today)}, '
    '${spokenMoney(bucket.amount)}';

/// Т3. Подпись графика для скринридера (ADR 0012, п. 5): «Расходы по дням за
/// октябрь. Больше всего 12 октября: 5400 рублей. В среднем 2400 рублей в
/// день». Нет среднего или ненулевой корзины — эти фразы пропускаются.
String dynamicsChartSpoken({
  required TransactionType type,
  required AnalyticsPeriod period,
  required BucketStep step,
  required List<Bucket> buckets,
  required Money? average,
  required DateOnly today,
}) {
  final parts = <String>[
    '${dynamicsTitle(type, step)} ${_spokenPeriod(period, today)}',
  ];
  Bucket? top;
  for (final b in buckets) {
    // При равенстве остаётся более ранняя корзина.
    if (!b.amount.isZero && (top == null || b.amount > top.amount)) top = b;
  }
  if (top != null) {
    parts.add(
      'Больше всего ${dynamicsBucketLabel(top, step, today)}: '
      '${spokenMoney(top.amount)}',
    );
  }
  if (average != null) {
    parts.add(dynamicsAverageText(average, step, spoken: true));
  }
  return parts.join('. ');
}

/// «за октябрь», «за 2026 год», «за 5–11 октября».
String _spokenPeriod(AnalyticsPeriod period, DateOnly today) {
  final start = period.range.start;
  return switch (period.kind) {
    PeriodKind.month =>
      'за ${formatMonthName(start)}'
          '${start.year == today.year ? '' : ' ${start.year}'}',
    PeriodKind.year => 'за ${start.year} год',
    _ => 'за ${formatPeriodLabel(period.kind, period.range, today: today)}',
  };
}

/// Т3. Чип фильтра категории в «Динамике» без выбора и заголовок листа.
const String dynamicsAllCategories = 'Все категории';
const String dynamicsCategorySheetTitle = 'Категория';

/// Пометка архивной категории в листе выбора.
const String dynamicsArchivedNote = 'В архиве';

/// Озвучка чипа: «Фильтр: Кафе, изменить».
String dynamicsCategoryChipSpoken(String name) => 'Фильтр: $name, изменить';
