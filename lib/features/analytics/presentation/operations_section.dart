import 'package:flutter/material.dart';
import 'package:money_app/core/format/date_format.dart';
import 'package:money_app/core/format/day_label.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/category_icon_view.dart';
import 'package:money_app/core/ui/category_labels.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/analytics/domain/operations_stats.dart';
import 'package:money_app/features/analytics/presentation/analytics_texts.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Раздел «Операции». Часть 1: «Крупные расходы» / «Крупные доходы» — до десяти
/// самых больших операций периода (ADR 0012, п. 4; тексты Т5).
///
/// Строка устроена как в «Истории» при сортировке по сумме. Касание зовёт
/// [onOpenTransaction]; маршрут правки открывает `lib/app/`. Список строится из
/// потока операций, поэтому после правки или удаления обновляется сам.
class OperationsSection extends StatelessWidget {
  const OperationsSection({
    required this.transactions,
    required this.range,
    required this.categories,
    required this.today,
    this.type = TransactionType.expense,
    this.onTypeSelected,
    this.onOpenTransaction,
    this.onOpenCategory,
    this.currency = rubCurrencyCode,
    super.key,
  });

  /// Операции окна данных; в «крупные» попадают только операции [range].
  final List<Transaction> transactions;
  final DateRange range;

  /// Все категории, включая архивные.
  final List<Category> categories;
  final DateOnly today;
  final TransactionType type;
  final ValueChanged<TransactionType>? onTypeSelected;
  final ValueChanged<Transaction>? onOpenTransaction;

  /// Касание строки «Частоты»: экран категории за текущий период.
  final ValueChanged<Category>? onOpenCategory;
  final String currency;

  static const typeKey = ValueKey('operations-type');
  static const listKey = ValueKey('operations-top-list');
  static const frequencyKey = ValueKey('operations-frequency');
  static const mostFrequentKey = ValueKey('operations-most-frequent');
  static Key statKey(String categoryId) =>
      ValueKey('operations-stat-$categoryId');
  static Key rowKey(String transactionId) =>
      ValueKey('operations-row-$transactionId');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final top = topTransactions(transactions, range, type, currency: currency);
    final byId = {for (final c in categories) c.id: c};
    final onTypeSelected = this.onTypeSelected;
    final onOpen = onOpenTransaction;
    final stats = categoryStats(transactions, range, type, currency: currency);
    // Категория, которой нет в справочнике («Без категории»), не становится
    // «Чаще всего», если есть хоть одна известная.
    final known = [
      for (final s in stats)
        if (byId.containsKey(s.categoryId)) s,
    ];
    final best = mostFrequentCategory(known.isEmpty ? stats : known);
    final onOpenCategory = this.onOpenCategory;

    final topCard = Card.outlined(
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
              header: true,
              child: Text(
                operationsTopTitle(type),
                style: theme.textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 8),
            if (top.isEmpty)
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
                  for (final t in top)
                    _OperationRow(
                      key: rowKey(t.id),
                      transaction: t,
                      category: byId[t.categoryId],
                      subcategory: t.subcategoryId == null
                          ? null
                          : byId[t.subcategoryId],
                      today: today,
                      onTap: onOpen == null ? null : () => onOpen(t),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
    // Нет «крупных» (все суммы нулевые) - второй карточки нет.
    if (best == null || top.isEmpty) return topCard;

    VoidCallback? openOf(String id) =>
        onOpenCategory == null || byId[id] == null
        ? null
        : () => onOpenCategory(byId[id]!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        topCard,
        const SizedBox(height: 16),
        Card.outlined(
          key: frequencyKey,
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
                Semantics(
                  header: true,
                  child: Text(
                    operationsFrequencyTitle(type),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  operationsMostFrequentText(
                    byId[best.categoryId]?.name ?? noCategoryLabel,
                    best.count,
                  ),
                  key: mostFrequentKey,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 8),
                for (final s in stats)
                  _StatRow(
                    key: statKey(s.categoryId),
                    category: byId[s.categoryId],
                    stat: s,
                    onTap: openOf(s.categoryId),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Строка категории в «Частоте»: иконка, название и «42 операции · средний чек
/// 610,00 ₽». Скринридер читает её одним узлом.
class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.category,
    required this.stat,
    required this.onTap,
    super.key,
  });

  /// `null` — категории нет в справочнике («Без категории»).
  final Category? category;
  final CategoryStat stat;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final name = category?.name ?? noCategoryLabel;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
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
                  Text(name, maxLines: 3, overflow: TextOverflow.ellipsis),
                  Text(
                    operationsStatSubtitle(stat.count, stat.average),
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      container: true,
      label: operationsStatSpoken(name, stat.count, stat.average),
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

/// День в строке: «Сегодня», «Вчера», «30 сентября» (с годом, если не текущий).
String _dayText(DateOnly day, DateOnly today) {
  if (day == today || day == today.addDays(-1)) {
    return dayLabel(day, today: today);
  }
  return day.year == today.year ? formatDayMonth(day) : formatDate(day);
}

/// Строка операции: иконка категории, «Категория · Подкатегория», «день ·
/// комментарий» и сумма. Скринридер читает её одним узлом.
class _OperationRow extends StatelessWidget {
  const _OperationRow({
    required this.transaction,
    required this.category,
    required this.subcategory,
    required this.today,
    required this.onTap,
    super.key,
  });

  final Transaction transaction;
  final Category? category;
  final Category? subcategory;
  final DateOnly today;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final isIncome = transaction.type == TransactionType.income;
    final accent = isIncome
        ? context.appColors.income
        : context.appColors.expense;
    final sign = isIncome ? '+' : String.fromCharCode(0x2212);
    final amountText = '$sign${formatMoney(transaction.amount)}';
    final title = category == null
        ? noCategoryLabel
        : subcategory == null
        ? category!.name
        : '${category!.name} · ${subcategory!.name}';
    final day = _dayText(transaction.occurredOn, today);
    final note = transaction.note;
    final spoken = StringBuffer(isIncome ? 'Доход ' : 'Расход ')
      ..write(spokenMoney(transaction.amount))
      ..write(', $title, $day');
    if (note != null) spoken.write(', комментарий: $note');

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: CategoryIconView(category?.iconKey, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                  Text(
                    note == null ? day : '$day · $note',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Сумма не шире 45% экрана: длинная при крупном шрифте уменьшается.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.45,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  amountText,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      container: true,
      label: spoken.toString(),
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
