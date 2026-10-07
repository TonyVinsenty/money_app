import 'package:flutter/material.dart';
import 'package:money_app/core/format/date_format.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/format/percent_format.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/async_view.dart';
import 'package:money_app/core/ui/category_labels.dart';
import 'package:money_app/core/ui/color_dot.dart';
import 'package:money_app/core/ui/donut_chart.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/analytics/domain/category_totals.dart';
import 'package:money_app/features/analytics/domain/period_summary.dart';
import 'package:money_app/features/analytics/domain/shares.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/home/presentation/month_summary_card.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Сколько строк легенды показываем: если секторов больше, три крупнейших и
/// строка «Ещё N категорий».
const int _legendRows = 4;

/// Внутренний отступ карточки, dp, и границы размера кольца.
const double _cardPadding = 16;
const double _minRing = 160;
const double _maxRing = 360;

/// Высота строки легенды, dp, и зазор между кольцом и легендой.
const double _legendRowHeight = 28;
const double _legendGap = 8;

/// Размер кольца: как можно крупнее по ширине карточки ([viewportWidth] минус
/// её отступы), но так, чтобы вместе с карточкой итогов, заголовком и легендой
/// оно помещалось в [viewportHeight]. Границы 160 и 360 dp. Высоты итогов,
/// заголовка и легенды прикидываем по масштабу шрифта [textScale].
double chartRingSize({
  required double viewportWidth,
  required double viewportHeight,
  required double textScale,
}) {
  // Отступы карточки сверху и снизу, заголовок, зазоры и строки легенды
  // (до двух по 28 dp; при крупном шрифте элементы встают по одному).
  final legendRows = textScale >= 1.5 ? 4 : 2;
  final summary = estimateSummaryHeight(
    viewportWidth - 2 * _cardPadding,
    textScale,
  );
  // Итоги и зазор 16 между карточками.
  final reserved =
      summary +
      16 +
      2 * _cardPadding +
      24 * textScale +
      12 +
      _legendGap +
      legendRows * _legendRowHeight;
  final byWidth = viewportWidth - 2 * _cardPadding;
  final byHeight = viewportHeight - reserved;
  return (byWidth < byHeight ? byWidth : byHeight).clamp(_minRing, _maxRing);
}

/// Карточка «Расходы по категориям» на «Главной»: кольцо размера [ringSize] с
/// балансом месяца («Всего») в центре и легенда под ним (до 4 элементов).
/// Касание сектора показывает в центре его категорию; отпускание пальца на
/// секторе и нажатие на элемент легенды зовут [onOpenCategory] с набором id
/// категорий.
/// Неизвестная категория («Без категории») никуда не ведёт.
///
/// Потоки [transactions] (операции месяца) и [categories] (все категории,
/// включая архивные) создаёт вызывающий и держит одними и теми же.
class MonthChartCard extends StatefulWidget {
  const MonthChartCard({
    required this.transactions,
    required this.categories,
    required this.month,
    required this.ringSize,
    this.onOpenCategory,
    this.isCurrentMonth = true,
    super.key,
  });

  /// Показан текущий месяц: от этого зависит текст пустого состояния.
  final bool isCurrentMonth;

  /// Диаметр кольца, dp (см. [chartRingSize]).
  final double ringSize;

  final Stream<List<Transaction>> transactions;
  final Stream<List<Category>> categories;

  /// Любой день показываемого месяца.
  final DateOnly month;

  /// Выбраны категории (сектор или строка легенды): id одной категории, группы
  /// «Остальное» или всех категорий строки «Ещё N». Без колбэка строки не
  /// кнопки, а сектора только подсвечиваются.
  final ValueChanged<Set<String>>? onOpenCategory;

  @override
  State<MonthChartCard> createState() => _MonthChartCardState();
}

/// Операции вместе с месяцем, для которого их запрашивали. При смене месяца
/// на экране остаются прежние операции, пока не придут новые: границы и
/// подписи берём из этой пары, а не из [MonthChartCard.month], иначе прежние
/// операции отфильтровались бы новым месяцем и мелькнуло бы «расходов нет».
typedef _MonthData = ({
  DateOnly month,
  bool isCurrentMonth,
  List<Transaction> transactions,
});

class _MonthChartCardState extends State<MonthChartCard> {
  int? _highlight;
  late Stream<_MonthData> _data = _tag();

  Stream<_MonthData> _tag() {
    final month = widget.month;
    final isCurrentMonth = widget.isCurrentMonth;
    return widget.transactions.map(
      (transactions) => (
        month: month,
        isCurrentMonth: isCurrentMonth,
        transactions: transactions,
      ),
    );
  }

  @override
  void didUpdateWidget(MonthChartCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Новый поток — новый месяц (или репозиторий): сектор под пальцем устарел.
    if (!identical(oldWidget.transactions, widget.transactions)) {
      _data = _tag();
      _highlight = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = AsyncView<_MonthData>(
      stream: _data,
      errorBuilder: _error,
      dataBuilder: (context, data) => AsyncView<List<Category>>(
        stream: widget.categories,
        errorBuilder: _error,
        dataBuilder: (context, categories) =>
            _content(context, data, categories),
      ),
    );
    return Card.outlined(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Расходы по категориям',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            // Кольцо по центру оставшейся высоты, легенда прижата к низу.
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  Widget _error(BuildContext context, Object error) {
    final theme = Theme.of(context);
    return Center(
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Не удалось посчитать расходы по категориям',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(
    BuildContext context,
    _MonthData data,
    List<Category> categories,
  ) {
    final transactions = data.transactions;
    final month = data.month;
    final theme = Theme.of(context);
    final colors = context.appColors;
    final range = monthRange(month);
    final balance = summarizePeriod(
      transactions,
      range,
      currency: rubCurrencyCode,
    ).balance;
    final slices = chartSlices(
      totalsByCategory(
        transactions,
        range,
        type: TransactionType.expense,
        currency: rubCurrencyCode,
      ),
    );
    final byId = {for (final c in categories) c.id: c};
    final names = {for (final c in categories) c.id: c.name};
    final open = widget.onOpenCategory;
    // Категории сектора; null — неизвестная категория («Без категории»).
    Set<String>? idsOf(ChartSlice s) {
      if (s.isOther) return s.categoryIds.toSet();
      final id = s.categoryIds.single;
      return byId.containsKey(id) ? {id} : null;
    }

    final items = _legendItems(
      slices,
      names,
      colors,
      onTap: open == null
          ? null
          : (s) {
              final ids = idsOf(s);
              return ids == null ? null : () => open(ids);
            },
      onTapRest: open == null
          ? null
          : () => open(legendRestCategoryIds(slices)),
    );
    // Номер мог устареть, если данные обновились во время касания.
    final lit = _highlight;
    final highlighted = lit != null && lit < slices.length ? lit : null;

    // spokenMoney сам добавляет «минус»; для плюса приставку ставим тут.
    final balanceSpoken = balance > Money.zero(rubCurrencyCode)
        ? 'плюс ${spokenMoney(balance)}'
        : spokenMoney(balance);
    final label =
        'Диаграмма расходов за ${formatMonthName(month)}. '
        'Всего: $balanceSpoken';

    final side = widget.ringSize;

    // Квадрат с жёсткими сторонами: карточка на «Главной» тянется по
    // intrinsic-высоте содержимого, а при одной лишь ширине кольцо мерилось бы
    // по всей ширине карточки, и экран прокручивался бы зря.
    final ring = SizedBox.square(
      dimension: side,
      child: DonutChart(
        segments: [
          for (var i = 0; i < slices.length; i++)
            DonutSegment(
              weight: slices[i].amount.minorUnits,
              color: _sliceColor(slices[i], i, colors),
            ),
        ],
        highlightedIndex: highlighted,
        onHighlight: (index) => setState(() => _highlight = index),
        onSelect: open == null
            ? null
            : (index) {
                if (index >= slices.length) return;
                final ids = idsOf(slices[index]);
                if (ids != null) open(ids);
              },
        semanticsLabel: label,
        center: SizedBox(
          width: side * 0.66,
          child: highlighted == null
              ? _totalCenter(theme, colors, balance)
              : _sliceCenter(
                  theme,
                  slices[highlighted],
                  slices[highlighted].isOther
                      ? 'Остальное'
                      : names[slices[highlighted].categoryIds.single] ??
                            noCategoryLabel,
                ),
        ),
      ),
    );

    final Widget legend = items.isEmpty
        ? Text(
            data.isCurrentMonth
                ? 'В этом месяце расходов пока нет'
                : 'За ${formatMonthName(month)} ${month.year} '
                      'расходов нет',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        : Wrap(
            alignment: WrapAlignment.center,
            spacing: 16,
            children: [for (final item in items) _LegendItemView(item: item)],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: Center(child: ring)),
        const SizedBox(height: _legendGap),
        legend,
      ],
    );
  }

  /// Центр без подсветки: «Всего» и баланс месяца (доходы минус расходы). Цвет и
  /// знак только у суммы: плюс цветом дохода, минус цветом расхода, ноль
  /// нейтрально.
  Widget _totalCenter(ThemeData theme, AppColors colors, Money balance) {
    final color = balance.isZero
        ? null
        : balance.isNegative
        ? colors.expense
        : colors.income;
    final text = balance.isZero || balance.isNegative
        ? formatMoney(balance)
        : '+${formatMoney(balance)}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _fit(
          Text(
            'Всего',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        _fit(
          Text(
            text,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(color: color),
          ),
        ),
      ],
    );
  }

  /// Строка в дырке кольца: длинная сумма уменьшается, а не вылезает.
  Widget _fit(Widget child) => FittedBox(fit: BoxFit.scaleDown, child: child);

  /// Центр при подсветке сектора: название, сумма и процент, всё нейтрально.
  Widget _sliceCenter(ThemeData theme, ChartSlice slice, String name) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        _fit(
          Text(
            formatMoney(slice.amount),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall,
          ),
        ),
        _fit(
          Text(
            _percentText(slice.share),
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// Строка легенды: цвет метки, подпись, сумма и доля.
class _LegendItem {
  const _LegendItem(
    this.label,
    this.amount,
    this.share,
    this.color, [
    this.onTap,
  ]);

  final String label;
  final Money amount;
  final PercentShare share;
  final Color color;

  /// Нажатие на строку; null — строка не кнопка.
  final VoidCallback? onTap;
}

/// Цвет сектора: по месту в палитре, «Остальное» — серый.
Color _sliceColor(ChartSlice slice, int index, AppColors colors) =>
    slice.isOther
    ? colors.chartOther
    : colors.chartPalette[index % colors.chartPalette.length];

List<_LegendItem> _legendItems(
  List<ChartSlice> slices,
  Map<String, String> names,
  AppColors colors, {
  VoidCallback? Function(ChartSlice slice)? onTap,
  VoidCallback? onTapRest,
}) {
  _LegendItem of(int i) {
    final s = slices[i];
    return _LegendItem(
      s.isOther ? 'Остальное' : names[s.categoryIds.single] ?? noCategoryLabel,
      s.amount,
      s.share,
      _sliceColor(s, i, colors),
      onTap?.call(s),
    );
  }

  if (slices.length <= _legendRows) {
    return [for (var i = 0; i < slices.length; i++) of(i)];
  }
  final rest = slices.sublist(_legendRows - 1);
  var count = 0;
  var percent = 0;
  var amount = Money.zero(rest.first.amount.currency);
  for (final s in rest) {
    count += s.categoryIds.length;
    percent += s.share.percent ?? 0;
    amount += s.amount;
  }
  return [
    for (var i = 0; i < _legendRows - 1; i++) of(i),
    _LegendItem(
      'Ещё $count ${pluralRu(count, 'категория', 'категории', 'категорий')}',
      amount,
      PercentShare(
        percent: percent,
        isBelowOne: amount.minorUnits > 0 && percent == 0,
      ),
      colors.chartOther,
      onTapRest,
    ),
  ];
}

/// Категории, не показанные отдельными элементами легенды (все секторы после
/// первых трёх, включая категории «Остального»): их открывает строка
/// «Ещё N категорий». Если секторов не больше [_legendRows], строки нет и
/// набор пуст.
Set<String> legendRestCategoryIds(List<ChartSlice> slices) {
  if (slices.length <= _legendRows) return {};
  return {for (final s in slices.skip(_legendRows - 1)) ...s.categoryIds};
}

class _LegendItemView extends StatelessWidget {
  const _LegendItemView({required this.item});

  final _LegendItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onTap = item.onTap;
    // Wrap даёт элементу не больше своей ширины: длинное название обрезается
    // многоточием, процент остаётся целым.
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ColorDot(color: item.color),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _percentText(item.share),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    // Строки очень компактные (28 dp): ниже рекомендованных 48 dp, зато легенда
    // не рыхлая; кольцо и сектора нажимаются тоже.
    final box = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _legendRowHeight),
      child: Center(widthFactor: 1, child: content),
    );
    return Semantics(
      // container: каждый элемент — отдельный узел, а не слитый с соседями.
      container: true,
      label:
          '${item.label}, ${spokenMoney(item.amount)}, '
          '${_percentSpoken(item.share)}',
      button: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      child: onTap == null
          ? box
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: box,
            ),
    );
  }
}

String _percentText(PercentShare share) =>
    formatPercent(share.percent ?? 0, isBelowOne: share.isBelowOne);

String _percentSpoken(PercentShare share) =>
    spokenPercent(share.percent ?? 0, isBelowOne: share.isBelowOne);
