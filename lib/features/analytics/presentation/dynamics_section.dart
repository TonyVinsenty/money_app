import 'package:flutter/material.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/bar_chart.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/domain/buckets.dart';
import 'package:money_app/features/analytics/presentation/analytics_texts.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Раздел «Динамика»: столбики расходов или доходов по дням (по месяцам для
/// года и длинного интервала), среднее и свёрнутый список ненулевых корзин
/// (ADR 0012, пп. 5–6; тексты Т3).
///
/// Выбранный пальцем столбик хранит сам раздел. Для вида «День» вместо графика
/// пояснение.
class DynamicsSection extends StatefulWidget {
  const DynamicsSection({
    required this.transactions,
    required this.period,
    required this.today,
    this.type = TransactionType.expense,
    this.onTypeSelected,
    this.currency = rubCurrencyCode,
    super.key,
  });

  /// Операции периода (лишние за его пределами игнорируются).
  final List<Transaction> transactions;
  final AnalyticsPeriod period;
  final DateOnly today;
  final TransactionType type;
  final ValueChanged<TransactionType>? onTypeSelected;
  final String currency;

  /// Ключи, на которые опираются тесты.
  static const typeKey = ValueKey('dynamics-type');
  static const chartKey = ValueKey('dynamics-chart');
  static const infoKey = ValueKey('dynamics-info');
  static const listKey = ValueKey('dynamics-list');

  @override
  State<DynamicsSection> createState() => _DynamicsSectionState();
}

class _DynamicsSectionState extends State<DynamicsSection> {
  int? _highlighted;

  @override
  void didUpdateWidget(DynamicsSection old) {
    super.didUpdateWidget(old);
    // Новый период или тип: прежний номер столбика ни к чему.
    if (old.period != widget.period || old.type != widget.type) {
      _highlighted = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final type = widget.type;
    final today = widget.today;
    final step = bucketStepFor(widget.period);
    final buckets = bucketTotals(
      widget.transactions,
      widget.period,
      type: type,
      currency: widget.currency,
    );
    final average = bucketAverage(buckets, today);
    final weights = [for (final b in buckets) b.amount.minorUnits];
    final onTypeSelected = widget.onTypeSelected;
    final colors = context.appColors;
    final highlighted = _highlighted != null && _highlighted! < buckets.length
        ? _highlighted
        : null;
    final nonZero = [
      for (final b in buckets)
        if (!b.amount.isZero) b,
    ];

    final Widget body;
    if (step == BucketStep.none) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          dynamicsDayHint,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(color: muted),
        ),
      );
    } else if (nonZero.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          comparisonNothingText(type),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(color: muted),
        ),
      );
    } else {
      final infoText = highlighted != null
          ? dynamicsSelectedText(buckets[highlighted], step, today)
          : average == null
          ? ''
          : dynamicsAverageText(average, step);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BarChart(
            key: DynamicsSection.chartKey,
            weights: weights,
            average: average?.minorUnits,
            color: type == TransactionType.expense
                ? colors.expense
                : colors.income,
            topLabel: formatMoney(
              Money.fromMinor(
                barChartCeiling(weights, average?.minorUnits),
                widget.currency,
              ),
            ),
            semanticsLabel: dynamicsChartSpoken(
              type: type,
              period: widget.period,
              step: step,
              buckets: buckets,
              average: average,
              today: today,
            ),
            highlightedIndex: highlighted,
            onHighlight: (index) => setState(() => _highlighted = index),
          ),
          const SizedBox(height: 8),
          // Текст под графиком читается как часть подписи графика, отдельно
          // его не озвучиваем.
          ExcludeSemantics(
            child: Text(
              infoText,
              key: DynamicsSection.infoKey,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ),
          ExpansionTile(
            key: DynamicsSection.listKey,
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            title: Text(dynamicsListTitle(step)),
            children: [
              for (final b in nonZero)
                Semantics(
                  container: true,
                  excludeSemantics: true,
                  label: dynamicsRowSpoken(b, step, today),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(dynamicsBucketLabel(b, step, today)),
                        ),
                        const SizedBox(width: 12),
                        Text(formatMoney(b.amount)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
    }

    return Card.outlined(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: SegmentedButton<TransactionType>(
                key: DynamicsSection.typeKey,
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
            if (step != BucketStep.none) ...[
              const SizedBox(height: 12),
              Text(
                dynamicsTitle(type, step),
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
            ] else
              const SizedBox(height: 8),
            body,
          ],
        ),
      ),
    );
  }
}
