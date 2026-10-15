import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:money_app/core/format/axis_tick.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/app_card.dart';
import 'package:money_app/core/ui/app_segmented_button.dart';
import 'package:money_app/core/ui/bar_chart.dart';
import 'package:money_app/core/ui/card_header.dart';
import 'package:money_app/core/ui/category_avatar.dart';
import 'package:money_app/core/ui/icon_scale.dart';
import 'package:money_app/core/ui/masked_amount.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/domain/buckets.dart';
import 'package:money_app/features/analytics/domain/pace.dart';
import 'package:money_app/features/analytics/presentation/analytics_texts.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
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
    this.categories = const [],
    this.categoryId,
    this.onCategorySelected,
    super.key,
  });

  /// Все категории, включая архивные (для чипа фильтра и листа выбора).
  final List<Category> categories;

  /// Выбранная категория фильтра; `null` — все. Если её нет среди доступных
  /// (архивная без операций этого типа в окне данных), фильтр не применяется
  /// и чип показывает «Все категории»: так график не врёт нулями. Сам выбор
  /// у владельца не стирается и вернётся, когда категория снова появится.
  final String? categoryId;

  /// Выбор в листе (`null` — «Все категории»). Без колбэка чипа нет.
  final ValueChanged<String?>? onCategorySelected;

  static const categoryChipKey = ValueKey('dynamics-category-chip');

  static ValueKey<String> categoryOptionKey(String? id) =>
      ValueKey('dynamics-category-${id ?? 'all'}');

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
  static const forecastKey = ValueKey('dynamics-forecast');
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
    if (old.period != widget.period ||
        old.type != widget.type ||
        old.categoryId != widget.categoryId) {
      _highlighted = null;
    }
  }

  /// Категории верхнего уровня текущего типа: живые и архивные, у которых
  /// есть операции этого типа в текущем периоде. По порядку категорий.
  List<Category> _categoryOptions() {
    final kind = widget.type == TransactionType.expense
        ? CategoryKind.expense
        : CategoryKind.income;
    final range = widget.period.range;
    final used = {
      for (final t in widget.transactions)
        if (t.type == widget.type && range.contains(t.occurredOn)) t.categoryId,
    };
    return [
      for (final c in widget.categories)
        if (c.isTopLevel &&
            c.kind == kind &&
            (!c.isArchived || used.contains(c.id)))
          c,
    ];
  }

  Future<void> _pickCategory(List<Category> options, Category? selected) async {
    final picked = await showModalBottomSheet<({String? id})>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Semantics(
                  header: true,
                  child: Text(
                    dynamicsCategorySheetTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              _option(context, null, dynamicsAllCategories, null, selected),
              for (final c in options)
                _option(context, c.id, c.name, c, selected),
            ],
          ),
        ),
      ),
    );
    if (picked != null) widget.onCategorySelected?.call(picked.id);
  }

  Widget _option(
    BuildContext context,
    String? id,
    String name,
    Category? category,
    Category? selected,
  ) {
    final isSelected = id == selected?.id;
    return ListTile(
      key: DynamicsSection.categoryOptionKey(id),
      leading: category == null
          ? const _AllCategoriesAvatar()
          : CategoryAvatar(category.iconKey, name: category.name),
      title: Text(name),
      subtitle: category != null && category.isArchived
          ? const Text(dynamicsArchivedNote)
          : null,
      trailing: isSelected ? const Icon(Icons.check) : null,
      selected: isSelected,
      onTap: () => Navigator.of(context).pop((id: id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final hidden = AmountsVisibility.hiddenOf(context);
    final type = widget.type;
    final today = widget.today;
    final step = bucketStepFor(widget.period);
    final options = _categoryOptions();
    final selected = widget.categoryId == null
        ? null
        : options.where((c) => c.id == widget.categoryId).firstOrNull;
    final buckets = bucketTotals(
      widget.transactions,
      widget.period,
      type: type,
      currency: widget.currency,
      categoryId: selected?.id,
    );
    final average = bucketAverage(buckets, today);
    final forecast = type == TransactionType.expense
        ? monthForecast(
            widget.transactions,
            widget.period,
            type,
            today,
            currency: widget.currency,
            categoryId: selected?.id,
          )
        : null;
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
    if (step == BucketStep.none || nonZero.isEmpty) {
      // Графика нет (его могли убрать посреди жеста): выбор не должен
      // «залипнуть» и вернуться, когда график появится снова. Это поле самого
      // состояния, setState в сборке не нужен.
      _highlighted = null;
    }
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
          selected == null
              ? comparisonNothingText(type)
              : dynamicsCategoryNothingText(selected.name, type),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(color: muted),
        ),
      );
    } else {
      final infoText = highlighted != null
          ? dynamicsSelectedText(
              buckets[highlighted],
              step,
              today,
              hidden: hidden,
            )
          : average == null
          ? ''
          : dynamicsAverageText(average, step, hidden: hidden);
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BarChart(
            key: DynamicsSection.chartKey,
            weights: weights,
            average: average?.minorUnits,
            axisLabels: dynamicsAxisLabels(widget.period, buckets),
            color: type == TransactionType.expense
                ? colors.expense
                : colors.income,
            // Вдвое выше прежнего (около 280 dp), но не больше 40 % экрана.
            height: math.min(280, MediaQuery.sizeOf(context).height * 0.4),
            zeroLabel: hidden
                ? maskedMoneyText
                : formatAxisTick(Money.fromMinor(0, widget.currency)),
            midLabel: hidden
                ? maskedMoneyText
                : formatAxisTick(
                    Money.fromMinor(
                      barScaleValues(weights, average?.minorUnits)[1],
                      widget.currency,
                    ),
                  ),
            topLabel: hidden
                ? maskedMoneyText
                : formatAxisTick(
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
              categoryName: selected?.name,
              hidden: hidden,
            ),
            highlightedIndex: highlighted,
            onHighlight: (index) => setState(() => _highlighted = index),
            // Дни после сегодня (по Clock) — бледной подложкой (И5).
            futureFrom: firstFutureBucket(buckets, today) < buckets.length
                ? firstFutureBucket(buckets, today)
                : null,
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
          if (forecast != null) ...[
            const SizedBox(height: 4),
            Semantics(
              container: true,
              excludeSemantics: true,
              label: dynamicsForecastText(
                forecast.forecast,
                widget.period.range.end,
                spoken: true,
                hidden: hidden,
              ),
              child: Text(
                dynamicsForecastText(
                  forecast.forecast,
                  widget.period.range.end,
                  hidden: hidden,
                ),
                key: DynamicsSection.forecastKey,
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ),
          ],
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
                  label: dynamicsRowSpoken(b, step, today, hidden: hidden),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 48),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(dynamicsBucketLabel(b, step, today)),
                        ),
                        const SizedBox(width: 12),
                        MaskedAmount(formatMoney(b.amount)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      );
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: AppSegmentedButton<TransactionType>(
              key: DynamicsSection.typeKey,
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
          if (step != BucketStep.none && widget.onCategorySelected != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: _CategoryChip(
                selected: selected,
                onPressed: () => _pickCategory(options, selected),
              ),
            ),
          ],
          if (step != BucketStep.none) ...[
            const SizedBox(height: 12),
            CardHeader(dynamicsTitle(type, step)),
          ] else
            const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }
}

/// Чип фильтра: «Все категории ▾» или имя выбранной категории.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.selected, required this.onPressed});

  final Category? selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final name = selected?.name ?? dynamicsAllCategories;
    return Semantics(
      label: dynamicsCategoryChipSpoken(name),
      button: true,
      onTap: onPressed,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        child: ActionChip(
          key: DynamicsSection.categoryChipKey,
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(name, overflow: TextOverflow.ellipsis)),
              const Icon(Icons.arrow_drop_down, size: 18),
            ],
          ),
          onPressed: onPressed,
          materialTapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
    );
  }
}

/// Кружок «Все категории» в листе выбора: тот же размер и заливка, что у
/// `CategoryAvatar`, значок `category_outlined`.
class _AllCategoriesAvatar extends StatelessWidget {
  const _AllCategoriesAvatar();

  @override
  Widget build(BuildContext context) {
    final k = iconScaleOf(context);
    return Container(
      width: 40 * k,
      height: 40 * k,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.category_outlined, size: 24 * k),
    );
  }
}
