import 'package:flutter/material.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/format/percent_format.dart';
import 'package:money_app/core/format/period_label.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/async_view.dart';
import 'package:money_app/core/ui/color_dot.dart';
import 'package:money_app/core/ui/donut_chart.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/domain/category_totals.dart';
import 'package:money_app/features/analytics/domain/shares.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';

const String _noSubcategoryLabel = 'Без подкатегории';
const String _unknownSubcategoryLabel = 'Неизвестная подкатегория';

/// Верхняя граница стороны кольца, dp.
const double _maxRing = 220;

/// Экран «Категория за период»: итог категории и её подкатегории (кольцо при
/// двух строках и больше, список со суммой и процентом).
///
/// Потоки [transactions] (операции периода) и [categories] (все категории,
/// включая архивные — для имён подкатегорий) создаёт вызывающий и держит
/// одними и теми же. Экран не знает ни репозиториев, ни маршрутов.
class CategoryBreakdownScreen extends StatefulWidget {
  const CategoryBreakdownScreen({
    required this.category,
    required this.period,
    required this.today,
    required this.transactions,
    required this.categories,
    super.key,
  });

  final Category category;
  final AnalyticsPeriod period;

  /// Сегодняшний день: от него зависит, как подписан период.
  final DateOnly today;
  final Stream<List<Transaction>> transactions;
  final Stream<List<Category>> categories;

  @override
  State<CategoryBreakdownScreen> createState() =>
      _CategoryBreakdownScreenState();
}

class _CategoryBreakdownScreenState extends State<CategoryBreakdownScreen> {
  int? _highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        // Только название: двухстрочный заголовок не помещается в тулбар 56 dp
        // при крупном шрифте. Период стоит в строке под тулбаром.
        title: Text(
          widget.category.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              formatPeriodLabel(
                widget.period.kind,
                widget.period.range,
                today: widget.today,
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: AsyncView<List<Transaction>>(
              stream: widget.transactions,
              errorBuilder: _error,
              dataBuilder: (context, transactions) => AsyncView<List<Category>>(
                stream: widget.categories,
                errorBuilder: _error,
                dataBuilder: (context, categories) =>
                    _content(context, transactions, categories),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _error(BuildContext context, Object error) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Не удалось посчитать итоги категории',
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
    List<Transaction> transactions,
    List<Category> categories,
  ) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final totals = subcategoryTotals(
      transactions,
      widget.period.range,
      categoryId: widget.category.id,
      currency: rubCurrencyCode,
    );
    if (totals.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Align(
          alignment: Alignment.topLeft,
          child: Text(
            'За этот период в категории операций нет',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final names = {for (final c in categories) c.id: c.name};
    final shares = percentShares([for (final t in totals) t.amount]);
    var total = Money.zero(rubCurrencyCode);
    for (final t in totals) {
      total += t.amount;
    }
    final rows = [
      for (var i = 0; i < totals.length; i++)
        _Row(
          label: totals[i].subcategoryId == null
              ? _noSubcategoryLabel
              : names[totals[i].subcategoryId] ?? _unknownSubcategoryLabel,
          amount: totals[i].amount,
          share: shares[i],
          // Палитра на 8 цветов: строки с 9-й получают серый «Остальное».
          color: i < colors.chartPalette.length
              ? colors.chartPalette[i]
              : colors.chartOther,
        ),
    ];
    final lit = _highlight;
    final highlighted = lit != null && lit < rows.length ? lit : null;
    final isExpense = widget.category.kind == CategoryKind.expense;
    final totalColor = isExpense ? colors.expense : colors.income;
    final totalText = isExpense
        ? '\u2212${formatMoney(total)}'
        : '+${formatMoney(total)}';

    final side = (MediaQuery.sizeOf(context).width - 32).clamp(120.0, _maxRing);
    final ringCenterWidth = side * 0.6;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Всего за период',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          totalText,
          style: theme.textTheme.headlineSmall?.copyWith(color: totalColor),
        ),
        if (rows.length >= 2) ...[
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              width: side,
              child: DonutChart(
                segments: [
                  for (var i = 0; i < rows.length; i++)
                    DonutSegment(
                      weight: rows[i].amount.minorUnits,
                      color: rows[i].color,
                    ),
                ],
                highlightedIndex: highlighted,
                onHighlight: (index) => setState(() => _highlight = index),
                semanticsLabel:
                    'Диаграмма по подкатегориям. Итог: ${spokenMoney(total)}',
                center: SizedBox(
                  width: ringCenterWidth,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SizedBox(
                      width: ringCenterWidth,
                      child: highlighted == null
                          ? _totalCenter(theme, totalText, totalColor)
                          : _rowCenter(theme, rows[highlighted]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _RowTile(row: rows[i]),
        ],
      ],
    );
  }

  Widget _totalCenter(ThemeData theme, String text, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Итого',
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

  /// Центр при подсветке: название, сумма и процент, всё нейтрально.
  Widget _rowCenter(ThemeData theme, _Row row) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          row.label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
        Text(
          formatMoney(row.amount),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        Text(
          row.percentText,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Строка списка: подкатегория (или «без подкатегории»), сумма, доля, цвет.
class _Row {
  const _Row({
    required this.label,
    required this.amount,
    required this.share,
    required this.color,
  });

  final String label;
  final Money amount;
  final PercentShare share;
  final Color color;

  String get percentText =>
      formatPercent(share.percent ?? 0, isBelowOne: share.isBelowOne);

  String get percentSpoken =>
      spokenPercent(share.percent ?? 0, isBelowOne: share.isBelowOne);
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.row});

  final _Row row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '${row.label}, ${spokenMoney(row.amount)}, ${row.percentSpoken}',
      excludeSemantics: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: ColorDot(color: row.color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.label, style: theme.textTheme.bodyMedium),
                Text(
                  '${formatMoney(row.amount)} · ${row.percentText}',
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
