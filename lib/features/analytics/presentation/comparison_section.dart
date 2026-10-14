import 'package:flutter/material.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/app_card.dart';
import 'package:money_app/core/ui/card_header.dart';
import 'package:money_app/core/ui/category_avatar.dart';
import 'package:money_app/core/ui/category_labels.dart';
import 'package:money_app/core/ui/category_stat_line.dart';
import 'package:money_app/core/ui/masked_amount.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';
import 'package:money_app/features/analytics/domain/period_comparison.dart';
import 'package:money_app/features/analytics/presentation/analytics_texts.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Раздел «Сравнение»: итог выбранного типа против периода сравнения и список
/// категорий с разницей (ADR 0012, п. 6; тексты Т2).
///
/// Разница цветом не красится: красный и зелёный в приложении значат только
/// «расход» и «доход», смысл передают стрелка и слова. Касание строки зовёт
/// [onOpenCategory]; без колбэка строки не кнопки.
class ComparisonSection extends StatelessWidget {
  const ComparisonSection({
    required this.transactions,
    required this.range,
    required this.previousRange,
    required this.categories,
    required this.today,
    this.type = TransactionType.expense,
    this.onTypeSelected,
    this.onOpenCategory,
    this.currency = rubCurrencyCode,
    super.key,
  });

  /// Операции окна данных: периода [range] и периода сравнения [previousRange].
  final List<Transaction> transactions;
  final DateRange range;
  final DateRange previousRange;

  /// Все категории, включая архивные.
  final List<Category> categories;
  final DateOnly today;
  final TransactionType type;
  final ValueChanged<TransactionType>? onTypeSelected;
  final ValueChanged<Category>? onOpenCategory;
  final String currency;

  /// Ключи, на которые опираются тесты.
  static const typeKey = ValueKey('comparison-type');
  static const totalKey = ValueKey('comparison-total');
  static const listKey = ValueKey('comparison-list');

  /// Ключ суммы в двухэтажной строке (крупный шрифт; для тестов раскладки).
  static const rowAmountKey = ValueKey('comparison-row-amount');

  static Key rowKey(String categoryId) =>
      ValueKey('comparison-row-$categoryId');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final total = comparePeriodTotals(
      transactions,
      range,
      previousRange,
      type: type,
      currency: currency,
    );
    final rows = compareByCategory(
      transactions,
      range,
      previousRange,
      type: type,
      currency: currency,
    );
    final byId = {for (final c in categories) c.id: c};
    final phrase = comparisonPhrase(previousRange, today);
    final onTypeSelected = this.onTypeSelected;
    final hidden = AmountsVisibility.hiddenOf(context);
    final isExpense = type == TransactionType.expense;
    final sign = total.current.isZero ? '' : (isExpense ? '−' : '+');
    final title = '$sign${formatMoney(total.current)}';
    final totalColor = isExpense
        ? context.appColors.expense
        : context.appColors.income;
    final summary = comparisonSummaryText(total, type, phrase, hidden: hidden);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: SegmentedButton<TransactionType>(
              key: typeKey,
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
          Semantics(
            container: true,
            excludeSemantics: true,
            label:
                '${comparisonTotalTitle(type, total.current, spoken: true, hidden: hidden)}. '
                '${comparisonSummaryText(total, type, phrase, spoken: true, hidden: hidden)}',
            child: Column(
              key: totalKey,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CardHeader(comparisonTotalHeading(type)),
                MaskedAmount(
                  title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: totalColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  summary,
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                comparisonNothingText(type),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(color: muted),
              ),
            )
          else
            Column(
              key: listKey,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final row in rows)
                  _ComparisonRow(
                    key: rowKey(row.categoryId),
                    category: byId[row.categoryId],
                    name: byId[row.categoryId]?.name ?? noCategoryLabel,
                    change: row,
                    onTap:
                        onOpenCategory == null || byId[row.categoryId] == null
                        ? null
                        : () => onOpenCategory!(byId[row.categoryId]!),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Строка категории: иконка, «Название · сумма» и под ней разница; при крупном
/// шрифте название и сумма — отдельными строками. Скринридер
/// читает её одним узлом.
class _ComparisonRow extends StatelessWidget {
  const _ComparisonRow({
    required this.category,
    required this.name,
    required this.change,
    required this.onTap,
    super.key,
  });

  /// `null` — категории нет в справочнике («Без категории»).
  final Category? category;
  final String name;
  final AmountChange change;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hidden = AmountsVisibility.hiddenOf(context);
    final content = CategoryStatLine(
      leading: CategoryAvatar(category?.iconKey, name: category?.name),
      name: name,
      amount: MaskedAmount(
        comparisonRowAmount(change),
        textKey: ComparisonSection.rowAmountKey,
        style: categoryAmountStyle(theme),
      ),
      subtitle: Text(
        comparisonRowDelta(change, hidden: hidden),
        style: categorySubtitleStyle(theme),
      ),
    );
    return Semantics(
      container: true,
      label: comparisonRowSpoken(name, change, hidden: hidden),
      button: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: AppRadius.borderM,
              child: content,
            ),
    );
  }
}
