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
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Сколько строк легенды показываем: если секторов больше, три крупнейших и
/// строка «Ещё N категорий».
const int _legendRows = 4;

/// Ширина «обвязки» вокруг карточки, dp: отступ экрана «Главной» (16 + 16) и
/// внутренний отступ карточки (16 + 16).
const double _chromeWidth = 64;

/// Легенда уходит под кольцо, если рядом не хватает места: кольцу нужно хотя бы
/// [_minRing] dp, зазору [_gap], а легенде [_legendWidth] dp, умноженные на
/// масштаб шрифта. На 360 dp при обычном шрифте легенда сбоку, при шрифте
/// около 115 % и больше (и на экранах уже ~340 dp) — под кольцом.
const double _minRing = 120;
const double _gap = 16;
const double _legendWidth = 140;

/// Карточка «Расходы по категориям» на «Главной»: кольцо с балансом месяца в
/// центре и легенда (до 4 строк). Касание сектора показывает в центре его
/// категорию; выбор сектора (переход) подключит шаг 4.11.
///
/// Потоки [transactions] (операции месяца) и [categories] (все категории,
/// включая архивные) создаёт вызывающий и держит одними и теми же.
class MonthChartCard extends StatefulWidget {
  const MonthChartCard({
    required this.transactions,
    required this.categories,
    required this.month,
    super.key,
  });

  final Stream<List<Transaction>> transactions;
  final Stream<List<Category>> categories;

  /// Любой день показываемого месяца.
  final DateOnly month;

  @override
  State<MonthChartCard> createState() => _MonthChartCardState();
}

class _MonthChartCardState extends State<MonthChartCard> {
  int? _highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = AsyncView<List<Transaction>>(
      stream: widget.transactions,
      errorBuilder: _error,
      dataBuilder: (context, transactions) => AsyncView<List<Category>>(
        stream: widget.categories,
        errorBuilder: _error,
        dataBuilder: (context, categories) =>
            _content(context, transactions, categories),
      ),
    );
    return Card.outlined(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Расходы по категориям',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 12),
            Expanded(child: Center(child: body)),
          ],
        ),
      ),
    );
  }

  Widget _error(BuildContext context, Object error) {
    final theme = Theme.of(context);
    return Row(
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
    );
  }

  Widget _content(
    BuildContext context,
    List<Transaction> transactions,
    List<Category> categories,
  ) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final range = monthRange(widget.month);
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
    final names = {for (final c in categories) c.id: c.name};
    final items = _legendItems(slices, names, colors);
    // Номер мог устареть, если данные обновились во время касания.
    final lit = _highlight;
    final highlighted = lit != null && lit < slices.length ? lit : null;

    // spokenMoney сам добавляет «минус»; для плюса приставку ставим тут.
    final balanceSpoken = balance > Money.zero(rubCurrencyCode)
        ? 'плюс ${spokenMoney(balance)}'
        : spokenMoney(balance);
    final label =
        'Диаграмма расходов за ${formatMonthName(widget.month)}. '
        'Баланс: $balanceSpoken';

    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final available = MediaQuery.sizeOf(context).width - _chromeWidth;
    final beside = available >= _minRing + _gap + _legendWidth * scale;
    final side = beside
        ? ((available - _gap) * 0.45).clamp(_minRing, 170.0)
        : available.clamp(_minRing, 200.0);

    final ring = SizedBox(
      width: side,
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
        semanticsLabel: label,
        center: SizedBox(
          width: side * 0.6,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: SizedBox(
              width: side * 0.6,
              child: highlighted == null
                  ? _balanceCenter(theme, colors, balance)
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
        ),
      ),
    );

    final Widget legend = items.isEmpty
        ? Text(
            'В этом месяце расходов пока нет',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _LegendRow(item: items[i]),
              ],
            ],
          );

    if (beside) {
      return Row(
        children: [
          ring,
          const SizedBox(width: _gap),
          Expanded(child: legend),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: ring),
        const SizedBox(height: 12),
        legend,
      ],
    );
  }

  /// Центр без подсветки: «Баланс» и сумма. Цвет и знак только у суммы.
  Widget _balanceCenter(ThemeData theme, AppColors colors, Money balance) {
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
        Text(
          'Баланс',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(color: color),
        ),
      ],
    );
  }

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
          style: theme.textTheme.bodySmall,
        ),
        Text(
          formatMoney(slice.amount),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        Text(
          _percentText(slice.share),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Строка легенды: цвет метки, подпись, сумма и доля.
class _LegendItem {
  const _LegendItem(this.label, this.amount, this.share, this.color);

  final String label;
  final Money amount;
  final PercentShare share;
  final Color color;
}

/// Цвет сектора: по месту в палитре, «Остальное» — серый.
Color _sliceColor(ChartSlice slice, int index, AppColors colors) =>
    slice.isOther
    ? colors.chartOther
    : colors.chartPalette[index % colors.chartPalette.length];

List<_LegendItem> _legendItems(
  List<ChartSlice> slices,
  Map<String, String> names,
  AppColors colors,
) {
  _LegendItem of(int i) {
    final s = slices[i];
    return _LegendItem(
      s.isOther ? 'Остальное' : names[s.categoryIds.single] ?? noCategoryLabel,
      s.amount,
      s.share,
      _sliceColor(s, i, colors),
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
    ),
  ];
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.item});

  final _LegendItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      // container: каждая строка — отдельный узел, а не слитая с соседями.
      container: true,
      label:
          '${item.label}, ${spokenMoney(item.amount)}, '
          '${_percentSpoken(item.share)}',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: ColorDot(color: item.color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  '${formatMoney(item.amount)} · ${_percentText(item.share)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _percentText(PercentShare share) =>
    formatPercent(share.percent ?? 0, isBelowOne: share.isBelowOne);

String _percentSpoken(PercentShare share) =>
    spokenPercent(share.percent ?? 0, isBelowOne: share.isBelowOne);
