import 'package:intl/intl.dart';
import 'package:money_app/core/format/date_format.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/format/percent_format.dart';
import 'package:money_app/core/format/period_label.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/masked_amount.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/domain/buckets.dart';
import 'package:money_app/features/analytics/domain/comparison.dart';
import 'package:money_app/features/analytics/domain/hints.dart';
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
    return 'в ${formatMonthPrepositional(start)}$yearSuffix';
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

/// Т2. Заголовок карточки итога: «Расходы» / «Доходы» (сумма - строкой ниже).
String comparisonTotalHeading(TransactionType type) =>
    type == TransactionType.expense ? 'Расходы' : 'Доходы';

/// Т2. Заголовок итога для скринридера: «Расходы: 48 200,00 ₽».
String comparisonTotalTitle(
  TransactionType type,
  Money total, {
  bool spoken = false,
  bool hidden = false,
}) =>
    '${type == TransactionType.expense ? 'Расходы' : 'Доходы'}: '
    '${_money(total, spoken: spoken, hidden: hidden)}';

/// Сумма для текста: словами при [spoken]; при [hidden] - скрыта.
String _money(Money m, {bool spoken = false, bool hidden = false}) {
  if (hidden) return spoken ? hiddenAmountLabel : maskedMoneyText;
  return spoken ? spokenMoney(m) : formatMoney(m);
}

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
  bool hidden = false,
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
  final money = _money(amount, spoken: spoken, hidden: hidden);
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
String comparisonRowTitle(
  String name,
  AmountChange change, {
  bool hidden = false,
}) {
  final now = _money(change.current, hidden: hidden);
  if (change.current.isZero && !change.previous.isZero) {
    return '$name · $now · было ${_money(change.previous, hidden: hidden)}';
  }
  return '$name · $now';
}

/// Т2. Вторая строка категории: «↑ на 2 300,00 ₽ (+40 %)»,
/// «↓ на 500,00 ₽ (\u22126 %)», «= столько же»; новая — «раньше не было».
String comparisonRowDelta(AmountChange change, {bool hidden = false}) {
  if (change.previous.isZero) return 'раньше не было';
  final difference = change.difference;
  if (difference.isZero) return '= столько же';
  final more = !difference.isNegative;
  final amount = _money(more ? difference : -difference, hidden: hidden);
  final arrow = more ? '↑' : '↓';
  final percent = change.percent!;
  return '$arrow на $amount (${signedPercent(percent, isBelowOne: percent == 0)})';
}

/// Т2. Озвучка строки категории: «Кафе, 8000 рублей, больше на 2300 рублей,
/// плюс 40 процентов».
String comparisonRowSpoken(
  String name,
  AmountChange change, {
  bool hidden = false,
}) {
  final now = _money(change.current, spoken: true, hidden: hidden);
  if (change.previous.isZero) return '$name, $now, раньше не было';
  final difference = change.difference;
  final percent = change.percent!;
  final percentText = spokenSignedPercent(percent, isBelowOne: percent == 0);
  if (change.current.isZero) {
    // Исчезнувшая категория: разница равна прежней сумме, не повторяем её.
    return '$name, $now, раньше было ${_money(change.previous, spoken: true, hidden: hidden)}, '
        '$percentText';
  }
  if (difference.isZero) return '$name, $now, столько же';
  final more = !difference.isNegative;
  final amount = _money(
    more ? difference : -difference,
    spoken: true,
    hidden: hidden,
  );
  return '$name, $now, ${more ? 'больше' : 'меньше'} на $amount, '
      '$percentText';
}

/// Т2. Когда в выбранном типе нет ничего ни сейчас, ни в сравнении.
String comparisonNothingText(TransactionType type) =>
    type == TransactionType.expense
    ? 'За этот период расходов нет'
    : 'За этот период доходов нет';

/// Т5. Заголовок списка в «Операциях».
String operationsTopTitle(TransactionType type) =>
    type == TransactionType.expense ? 'Крупные расходы' : 'Крупные доходы';

/// Т5. Заголовок второй карточки «Операций»: «Частота и средний чек расходов».
String operationsFrequencyTitle(TransactionType type) =>
    'Частота и средний чек '
    '${type == TransactionType.expense ? 'расходов' : 'доходов'}';

final String _emDash = String.fromCharCode(0x2014);

/// Т5. «42 операции» (склонение по числу).
String operationsCountText(int count) =>
    '$count ${pluralRu(count, 'операция', 'операции', 'операций')}';

/// Т5. «Чаще всего — Продукты (42 операции)».
String operationsMostFrequentText(String name, int count) =>
    'Чаще всего $_emDash $name (${operationsCountText(count)})';

/// Т5. Вторая строка категории: «42 операции · средний чек 610,00 ₽».
String operationsStatSubtitle(
  int count,
  Money average, {
  bool hidden = false,
}) =>
    '${operationsCountText(count)} · средний чек '
    '${_money(average, hidden: hidden)}';

/// Т5. Озвучка строки: «Продукты, 42 операции, средний чек 610 рублей».
String operationsStatSpoken(
  String name,
  int count,
  Money average, {
  bool hidden = false,
}) =>
    '$name, ${operationsCountText(count)}, '
    'средний чек ${_money(average, spoken: true, hidden: hidden)}';

/// Т6. Заголовок карточки подсказок: виден только скринридеру.
const String analyticsHintsTitle = 'Подсказки по расходам';

/// Т6. Дни недели в дательном падеже («по субботам»), индекс 0 — понедельник.
const List<String> _weekdaysDative = [
  'понедельникам',
  'вторникам',
  'средам',
  'четвергам',
  'пятницам',
  'субботам',
  'воскресеньям',
];

/// Т6. Хвост правила 1 — «за весь» прошлый период: «за весь сентябрь»,
/// «за всю прошлую неделю», «за весь 2025 год», «вчера за весь день»,
/// «за предыдущие 10 дней» (свой интервал). Год у месяца — если он не тот же,
/// что у [today].
String _wholePreviousTail(AnalyticsPeriod period, DateOnly today) {
  final previous = previousPeriod(period);
  if (previous == null) {
    final days = period.range.lengthInDays;
    return 'за предыдущие $days ${pluralRu(days, 'день', 'дня', 'дней')}';
  }
  final start = previous.range.start;
  return switch (period.kind) {
    PeriodKind.day => 'вчера за весь день',
    PeriodKind.week => 'за всю прошлую неделю',
    PeriodKind.month =>
      'за весь ${formatMonthName(start)}'
          '${start.year == today.year ? '' : ' ${start.year}'}',
    PeriodKind.year => 'за весь ${start.year} год',
    PeriodKind.custom => throw StateError('custom has no previous period'),
  };
}

/// Т6. Строка подсказки.
///
/// 1. «Кафе: уже потрачено 8 000,00 ₽ — больше, чем за весь сентябрь (6 500,00 ₽)»;
/// 2. «Продукты: средний чек на 18 % больше, чем 1–11 сентября»
///    («меньше», если снизился);
/// 3. «Больше всего тратите по субботам — 28 % расходов».
///
/// [nameOf] даёт название категории (его не склоняем, поэтому «Категория: …»).
/// Для скринридера ([spoken]) суммы и проценты словами, без тире и скобок.
/// Подсказку правила 1 показывают только для периода с сегодняшним днём.
String analyticsHintText(
  AnalyticsHint hint, {
  required String Function(String categoryId) nameOf,
  required AnalyticsPeriod period,
  required DateOnly today,
  bool spoken = false,
  bool hidden = false,
}) {
  switch (hint) {
    case CategoryAbovePreviousHint():
      final now = _money(hint.current, spoken: spoken, hidden: hidden);
      final before = _money(hint.previousTotal, spoken: spoken, hidden: hidden);
      final tail = _wholePreviousTail(period, today);
      final name = nameOf(hint.categoryId);
      return spoken
          ? '$name: уже потрачено $now, больше, чем $tail, $before'
          : '$name: уже потрачено $now $_emDash больше, чем $tail ($before)';
    case AverageCheckChangeHint():
      final value = hint.percent.abs();
      final percent = spoken
          ? '$value ${pluralRu(value, 'процент', 'процента', 'процентов')}'
          : '${_percentFormat.format(value)}$_nbsp%';
      final phrase = comparisonPhrase(comparisonRange(period, today), today);
      return '${nameOf(hint.categoryId)}: средний чек на $percent '
          '${hint.percent > 0 ? 'больше' : 'меньше'}, чем $phrase';
    case BusiestWeekdayHint():
      final day = _weekdaysDative[hint.weekday - 1];
      final share = hint.sharePercent;
      final percent = spoken
          ? '$share ${pluralRu(share, 'процент', 'процента', 'процентов')}'
          : '${_percentFormat.format(share)}$_nbsp%';
      return spoken
          ? 'Больше всего тратите по $day, $percent расходов'
          : 'Больше всего тратите по $day $_emDash $percent расходов';
  }
}

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
  bool hidden = false,
}) =>
    'В среднем ${_money(average, spoken: spoken, hidden: hidden)} '
    '${step == BucketStep.month ? 'в месяц' : 'в день'}';

/// Т4. Прогноз: «Если тратить так же, к 31 октября будет ≈ 74 000,00 ₽».
/// Для скринридера ([spoken]) «примерно» и сумма словами.
String dynamicsForecastText(
  Money forecast,
  DateOnly monthEnd, {
  bool spoken = false,
  bool hidden = false,
}) =>
    'Если тратить так же, к ${formatDayMonth(monthEnd)} будет '
    '${spoken ? 'примерно ' : '≈ '}'
    '${_money(forecast, spoken: spoken, hidden: hidden)}';

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
String dynamicsSelectedText(
  Bucket bucket,
  BucketStep step,
  DateOnly today, {
  bool hidden = false,
}) =>
    '${dynamicsBucketLabel(bucket, step, today)}: '
    '${_money(bucket.amount, hidden: hidden)}';

/// Первые буквы месяцев для подписей оси («Я Ф М А М И И А С О Н Д»).
const String _monthInitials = 'ЯФМАМИИАСОНД';

const List<String> _weekdayShort = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

String _twoDigits(int n) => n.toString().padLeft(2, '0');

/// Т3. Подписи оси под столбиками: номер столбика -> короткая строка.
///
/// Месяц: «1», «10», «20» и последний день. Неделя: «Пн»…«Вс». Год: первые
/// буквы всех 12 месяцев. Свой интервал по дням: первый, средний и последний
/// день как «15.12». Свой по месяцам: первые буквы месяцев, при больше чем 12
/// месяцах каждый второй (до 24), а дальше каждый третий, чтобы не налезали.
/// Для вида «День» (корзин нет) подписей нет.
Map<int, String> dynamicsAxisLabels(
  AnalyticsPeriod period,
  List<Bucket> buckets,
) {
  final n = buckets.length;
  if (n == 0) return const {};
  DateOnly start(int i) => buckets[i].range.start;
  String initial(int i) => _monthInitials[start(i).month - 1];
  switch (period.kind) {
    case PeriodKind.day:
      return const {};
    case PeriodKind.week:
      return {
        for (var i = 0; i < n; i++)
          i: _weekdayShort[start(i).toDateTime().weekday - 1],
      };
    case PeriodKind.month:
      return {
        for (var i = 0; i < n; i++)
          if (i == n - 1 || const {1, 10, 20}.contains(start(i).day))
            i: '${start(i).day}',
      };
    case PeriodKind.year:
      return {for (var i = 0; i < n; i++) i: initial(i)};
    case PeriodKind.custom:
      if (bucketStepFor(period) == BucketStep.month) {
        final stride = n <= 12
            ? 1
            : n <= 24
            ? 2
            : 3;
        return {for (var i = 0; i < n; i += stride) i: initial(i)};
      }
      return {
        for (final i in {0, n ~/ 2, n - 1})
          i: '${_twoDigits(start(i).day)}.${_twoDigits(start(i).month)}',
      };
  }
}

/// Т3. Пояснение вместо графика для вида «День».
const String dynamicsDayHint =
    'Выберите неделю, месяц, год или свой период — здесь появятся '
    'столбики по дням';

/// Т3. Название свёрнутого списка: «По дням» / «По месяцам».
String dynamicsListTitle(BucketStep step) =>
    step == BucketStep.month ? 'По месяцам' : 'По дням';

/// Т3. Строка списка для скринридера: «12 октября, 5400 рублей».
String dynamicsRowSpoken(
  Bucket bucket,
  BucketStep step,
  DateOnly today, {
  bool hidden = false,
}) =>
    '${dynamicsBucketLabel(bucket, step, today)}, '
    '${_money(bucket.amount, spoken: true, hidden: hidden)}';

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
  String? categoryName,
  bool hidden = false,
}) {
  final category = categoryName == null ? '' : ', категория $categoryName,';
  final parts = <String>[
    '${dynamicsTitle(type, step)}$category ${_spokenPeriod(period, today)}',
  ];
  Bucket? top;
  for (final b in buckets) {
    // При равенстве остаётся более ранняя корзина.
    if (!b.amount.isZero && (top == null || b.amount > top.amount)) top = b;
  }
  if (top != null) {
    parts.add(
      'Больше всего ${dynamicsBucketLabel(top, step, today)}: '
      '${_money(top.amount, spoken: true, hidden: hidden)}',
    );
  }
  if (average != null) {
    parts.add(dynamicsAverageText(average, step, spoken: true, hidden: hidden));
  }
  return parts.join('. ');
}

/// «за октябрь», «за 2026 год», «с 5 по 11 октября», «с 15 декабря 2025 по
/// 20 февраля 2026». Год у недели — если она не в году [today], у своего
/// интервала — всегда.
String _spokenPeriod(AnalyticsPeriod period, DateOnly today) {
  final start = period.range.start;
  final end = period.range.end;
  switch (period.kind) {
    case PeriodKind.month:
      return 'за ${formatMonthName(start)}'
          '${start.year == today.year ? '' : ' ${start.year}'}';
    case PeriodKind.year:
      return 'за ${start.year} год';
    case PeriodKind.day:
    case PeriodKind.week:
    case PeriodKind.custom:
      if (start == end) {
        return 'за ${formatPeriodLabel(period.kind, period.range, today: today)}';
      }
      if (start.year != end.year) {
        return 'с ${formatDayMonth(start)} ${start.year} '
            'по ${formatDayMonth(end)} ${end.year}';
      }
      final withYear =
          period.kind == PeriodKind.custom || start.year != today.year;
      final year = withYear ? ' ${end.year}' : '';
      final from = start.month == end.month
          ? '${start.day}'
          : formatDayMonth(start);
      return 'с $from по ${formatDayMonth(end)}$year';
  }
}

/// Т3. Чип фильтра категории в «Динамике» без выбора и заголовок листа.
const String dynamicsAllCategories = 'Все категории';
const String dynamicsCategorySheetTitle = 'Категория';

/// Пометка архивной категории в листе выбора.
const String dynamicsArchivedNote = 'В архиве';

/// Озвучка чипа: «Категория: Кафе, изменить».
String dynamicsCategoryChipSpoken(String name) => 'Категория: $name, изменить';

/// Пустой график при выбранной категории: «В категории «Кафе» за этот период
/// расходов нет».
String dynamicsCategoryNothingText(String name, TransactionType type) =>
    'В категории «$name» за этот период '
    '${type == TransactionType.expense ? 'расходов' : 'доходов'} нет';

/// Название вида периода на кнопке шапки и в её меню.
String periodKindTitle(PeriodKind kind) => switch (kind) {
  PeriodKind.day => 'День',
  PeriodKind.week => 'Неделя',
  PeriodKind.month => 'Месяц',
  PeriodKind.year => 'Год',
  PeriodKind.custom => 'Свой период',
};

/// Пункт меню для выбора своих дат.
const String periodCustomMenuItem = 'Свой период\u2026';

/// Озвучка кнопки вида периода: «Период: месяц, изменить».
String periodKindSpoken(PeriodKind kind) {
  final name = switch (kind) {
    PeriodKind.day => 'день',
    PeriodKind.week => 'неделя',
    PeriodKind.month => 'месяц',
    PeriodKind.year => 'год',
    PeriodKind.custom => 'свой',
  };
  return 'Период: $name, изменить';
}
