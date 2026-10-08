import 'package:flutter/material.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/format/percent_format.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/category_icon_view.dart';
import 'package:money_app/core/ui/category_labels.dart';
import 'package:money_app/core/ui/color_dot.dart';
import 'package:money_app/core/ui/donut_chart.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/analytics/domain/category_totals.dart';
import 'package:money_app/features/analytics/domain/shares.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Внутренний отступ карточки и границы размера кольца, dp.
const double _cardPadding = 16;
const double _minRing = 160;
const double _maxRing = 320;

/// Расходы или доходы периода по категориям: карточка с переключателем типа,
/// кольцом и полным списком категорий. Если операций выбранного типа нет, вместо
/// кольца и списка текст, а переключатель остаётся.
///
/// Касание сектора показывает в центре его категорию; отпускание пальца на
/// секторе и нажатие на строку списка зовут [onOpenCategory]. Сектор
/// «Остальное» только подсвечивается, неизвестная категория («Без
/// категории») никуда не ведёт. Без [onOpenCategory] строки не кнопки.
class CategoryBreakdownCard extends StatefulWidget {
  const CategoryBreakdownCard({
    required this.transactions,
    required this.range,
    required this.categories,
    this.type = TransactionType.expense,
    this.onTypeSelected,
    this.onOpenCategory,
    this.currency = rubCurrencyCode,
    super.key,
  });

  /// Код валюты, в которой считаются суммы (основная валюта).
  final String currency;

  /// Операции периода [range].
  final List<Transaction> transactions;
  final DateRange range;

  /// Все категории, включая архивные.
  final List<Category> categories;

  /// Какие операции показаны: расходы или доходы.
  final TransactionType type;

  /// Выбран другой тип в переключателе. Без колбэка переключатель недоступен.
  final ValueChanged<TransactionType>? onTypeSelected;

  final ValueChanged<Category>? onOpenCategory;

  /// Ключ переключателя «Расходы | Доходы».
  static const typeKey = ValueKey('category-breakdown-type');

  /// Ключ карточки с кольцом.
  static const cardKey = ValueKey('category-breakdown-card');

  /// Ключ списка категорий.
  static const listKey = ValueKey('category-breakdown-list');

  /// Ключ строки списка категории с id [categoryId].
  static Key rowKey(String categoryId) =>
      ValueKey('category-breakdown-row-$categoryId');

  /// Ключ метки цвета в строке категории [categoryId].
  static Key dotKey(String categoryId) =>
      ValueKey('category-breakdown-dot-$categoryId');

  @override
  State<CategoryBreakdownCard> createState() => _CategoryBreakdownCardState();
}

class _CategoryBreakdownCardState extends State<CategoryBreakdownCard> {
  int? _highlight;

  @override
  void didUpdateWidget(CategoryBreakdownCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Другой тип — другие сектора: сектор под пальцем устарел.
    if (oldWidget.type != widget.type) _highlight = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = widget.type;
    final isExpense = type == TransactionType.expense;
    final totals = totalsByCategory(
      widget.transactions,
      widget.range,
      type: type,
      currency: widget.currency,
    );
    final byId = {for (final c in widget.categories) c.id: c};
    final open = widget.onOpenCategory;
    final onTypeSelected = widget.onTypeSelected;

    return Card.outlined(
      key: CategoryBreakdownCard.cardKey,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(_cardPadding),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = constraints.maxWidth.clamp(_minRing, _maxRing);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: SegmentedButton<TransactionType>(
                    key: CategoryBreakdownCard.typeKey,
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: TransactionType.expense,
                        label: Text('Расходы'),
                      ),
                      ButtonSegment(
                        value: TransactionType.income,
                        label: Text('Доходы'),
                      ),
                    ],
                    selected: {type},
                    onSelectionChanged: onTypeSelected == null
                        ? null
                        : (selected) => onTypeSelected(selected.first),
                  ),
                ),
                const SizedBox(height: 12),
                if (totals.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      isExpense
                          ? 'За этот период расходов нет'
                          : 'За этот период доходов нет',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                else
                  ..._chart(context, totals, byId, side, open),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Кольцо и полный список категорий для непустых итогов [totals].
  List<Widget> _chart(
    BuildContext context,
    List<CategoryTotal> totals,
    Map<String, Category> byId,
    double side,
    ValueChanged<Category>? open,
  ) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final type = widget.type;
    final slices = chartSlices(totals);
    final shares = percentShares([for (final t in totals) t.amount]);
    final isExpense = type == TransactionType.expense;
    final total = Money.fromMinor(
      totals.fold<int>(0, (sum, t) => sum + t.amount.minorUnits),
      widget.currency,
    );

    // Цвет категории: цвет её сектора, у попавших в «Остальное» — серый.
    final colorOf = <String, Color>{};
    for (var i = 0; i < slices.length; i++) {
      final color = _sliceColor(slices[i], i, colors);
      for (final id in slices[i].categoryIds) {
        colorOf[id] = color;
      }
    }
    String nameOf(String id) => byId[id]?.name ?? noCategoryLabel;

    // Номер мог устареть, если данные обновились во время касания.
    final lit = _highlight;
    final highlighted = lit != null && lit < slices.length ? lit : null;

    final label = isExpense ? 'Расходы' : 'Доходы';
    final totalSpoken = isExpense
        ? 'минус ${spokenMoney(total)}'
        : 'плюс ${spokenMoney(total)}';
    final what = isExpense ? 'расходов' : 'доходов';

    return [
      Center(
        child: SizedBox.square(
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
                    final slice = slices[index];
                    if (slice.isOther) return;
                    final category = byId[slice.categoryIds.single];
                    if (category != null) open(category);
                  },
            semanticsLabel:
                'Диаграмма $what по категориям. $label: $totalSpoken',
            center: SizedBox(
              width: side * 0.66,
              child: highlighted == null
                  ? _totalCenter(theme, colors, total, label, isExpense)
                  : _sliceCenter(
                      theme,
                      slices[highlighted],
                      slices[highlighted].isOther
                          ? 'Остальное'
                          : nameOf(slices[highlighted].categoryIds.single),
                    ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Column(
        key: CategoryBreakdownCard.listKey,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < totals.length; i++)
            _CategoryRow(
              key: CategoryBreakdownCard.rowKey(totals[i].categoryId),
              dotKey: CategoryBreakdownCard.dotKey(totals[i].categoryId),
              category: byId[totals[i].categoryId],
              name: nameOf(totals[i].categoryId),
              amount: totals[i].amount,
              type: type,
              share: shares[i],
              color: colorOf[totals[i].categoryId]!,
              onTap: open == null || byId[totals[i].categoryId] == null
                  ? null
                  : () => open(byId[totals[i].categoryId]!),
            ),
        ],
      ),
    ];
  }

  /// Центр без подсветки: подпись типа и сумма всех его категорий, со знаком и
  /// цветом, как в строках списка.
  Widget _totalCenter(
    ThemeData theme,
    AppColors colors,
    Money total,
    String label,
    bool isExpense,
  ) {
    final color = isExpense ? colors.expense : colors.income;
    final text = isExpense
        ? '\u2212${formatMoney(total)}'
        : '+${formatMoney(total)}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _fit(
          Text(
            label,
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

  /// Строка в дырке кольца: длинная сумма уменьшается, а не вылезает.
  Widget _fit(Widget child) => FittedBox(fit: BoxFit.scaleDown, child: child);
}

/// Цвет сектора: по месту в палитре, «Остальное» — серый.
Color _sliceColor(ChartSlice slice, int index, AppColors colors) =>
    slice.isOther
    ? colors.chartOther
    : colors.chartPalette[index % colors.chartPalette.length];

String _percentText(PercentShare share) =>
    formatPercent(share.percent ?? 0, isBelowOne: share.isBelowOne);

String _percentSpoken(PercentShare share) =>
    spokenPercent(share.percent ?? 0, isBelowOne: share.isBelowOne);

/// Строка списка: метка цвета, иконка, название, сумма и процент. Скринридер
/// читает её целиком одним узлом; метка цвета и иконка для него пусты.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.dotKey,
    required this.category,
    required this.name,
    required this.amount,
    required this.type,
    required this.share,
    required this.color,
    required this.onTap,
    super.key,
  });

  final Key dotKey;

  /// `null` — категории нет в справочнике («Без категории»).
  final Category? category;
  final String name;
  final Money amount;
  final TransactionType type;
  final PercentShare share;
  final Color color;

  /// `null` — строка не кнопка.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final isExpense = type == TransactionType.expense;
    final colors = context.appColors;
    // Знак и цвет по типу, как в карточке итогов; скринридеру — «минус»/«плюс».
    final amountText = isExpense
        ? '\u2212${formatMoney(amount)}'
        : '+${formatMoney(amount)}';
    final amountColor = isExpense ? colors.expense : colors.income;
    final spokenAmount = isExpense
        ? 'минус ${spokenMoney(amount)}'
        : 'плюс ${spokenMoney(amount)}';
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            ColorDot(key: dotKey, color: color),
            const SizedBox(width: 12),
            ExcludeSemantics(
              child: CategoryIconView(
                category?.iconKey,
                size: 24,
                color: muted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text(
                    amountText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: amountColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _percentText(share),
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      // container: каждая строка — отдельный узел, а не слитый с соседями.
      container: true,
      label: '$name, $spokenAmount, ${_percentSpoken(share)}',
      button: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: content,
            ),
    );
  }
}
