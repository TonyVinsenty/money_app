import 'package:flutter/material.dart';
import 'package:money_app/core/format/date_format.dart';
import 'package:money_app/core/format/day_label.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/format/percent_format.dart';
import 'package:money_app/core/format/period_label.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/async_view.dart';
import 'package:money_app/core/ui/card_header.dart';
import 'package:money_app/core/ui/category_avatar.dart';
import 'package:money_app/core/ui/category_stat_line.dart';
import 'package:money_app/core/ui/donut_chart.dart';
import 'package:money_app/core/ui/masked_amount.dart';
import 'package:money_app/core/ui/operation_tile.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/domain/category_totals.dart';
import 'package:money_app/features/analytics/domain/shares.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

const String _noSubcategoryLabel = 'Без подкатегории';
const String _unknownSubcategoryLabel = 'Неизвестная подкатегория';

/// День в строке: «Сегодня», «Вчера», «30 сентября» (с годом, если не текущий).
String _operationDay(DateOnly day, DateOnly today) {
  if (day == today || day == today.addDays(-1)) {
    return dayLabel(day, today: today);
  }
  return day.year == today.year ? formatDayMonth(day) : formatDate(day);
}

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
    this.currency = rubCurrencyCode,
    this.onOpenTransaction,
    super.key,
  });

  /// Касание строки операции: правку открывает `lib/app/`.
  final ValueChanged<Transaction>? onOpenTransaction;

  /// Код валюты, в которой считаются суммы (основная валюта).
  final String currency;

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
      currency: widget.currency,
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

    final operations = _categoryOperations(transactions);
    final names = {for (final c in categories) c.id: c.name};
    final icons = {for (final c in categories) c.id: c.iconKey};
    final shares = percentShares([for (final t in totals) t.amount]);
    var total = Money.zero(widget.currency);
    for (final t in totals) {
      total += t.amount;
    }
    final isExpense = widget.category.kind == CategoryKind.expense;
    final rows = [
      for (var i = 0; i < totals.length; i++)
        _Row(
          label: totals[i].subcategoryId == null
              ? _noSubcategoryLabel
              : names[totals[i].subcategoryId] ?? _unknownSubcategoryLabel,
          iconKey: icons[totals[i].subcategoryId] ?? widget.category.iconKey,
          avatarName: icons.containsKey(totals[i].subcategoryId)
              ? names[totals[i].subcategoryId]
              : widget.category.name,
          amount: totals[i].amount,
          isExpense: isExpense,
          amountColor: isExpense ? colors.expense : colors.income,
          share: shares[i],
          // Палитра на 8 цветов: строки с 9-й получают серый «Остальное».
          color: i < colors.chartPalette.length
              ? colors.chartPalette[i]
              : colors.chartOther,
        ),
    ];
    final lit = _highlight;
    final highlighted = lit != null && lit < rows.length ? lit : null;
    final totalColor = isExpense ? colors.expense : colors.income;
    final totalText = isExpense
        ? '\u2212${formatMoney(total)}'
        : '+${formatMoney(total)}';

    final side = (MediaQuery.sizeOf(context).width - 32).clamp(120.0, _maxRing);
    final ringCenterWidth = side * 0.6;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.l),
      children: [
        Text(
          'Всего за период',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        MaskedAmount(
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
                    'Диаграмма по подкатегориям. Всего: '
                    '${maskedSpoken(context, spokenMoney(total))}',
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
        if (operations.isNotEmpty) ...[
          const SizedBox(height: 24),
          const CardHeader('Операции'),
          for (final t in operations)
            _operationTile(
              t,
              names: names,
              icons: icons,
              onOpen: widget.onOpenTransaction,
            ),
        ],
      ],
    );
  }

  /// Операции этой категории (с подкатегориями) за период, новые сверху.
  List<Transaction> _categoryOperations(List<Transaction> transactions) {
    final result = [
      for (final t in transactions)
        if (t.categoryId == widget.category.id &&
            t.amount.currency == widget.currency &&
            widget.period.range.contains(t.occurredOn))
          t,
    ];
    result.sort((a, b) {
      final byDay = b.occurredOn.compareTo(a.occurredOn);
      if (byDay != 0) return byDay;
      final byTime = b.occurredAt.compareTo(a.occurredAt);
      return byTime != 0 ? byTime : b.id.compareTo(a.id);
    });
    return result;
  }

  Widget _operationTile(
    Transaction t, {
    required Map<String, String> names,
    required Map<String, String?> icons,
    required ValueChanged<Transaction>? onOpen,
  }) {
    final isIncome = t.type == TransactionType.income;
    final subId = t.subcategoryId;
    final title = subId == null
        ? widget.category.name
        : names[subId] ?? _unknownSubcategoryLabel;
    final day = _operationDay(t.occurredOn, widget.today);
    final note = t.note;
    final spoken = StringBuffer(isIncome ? 'Доход ' : 'Расход ')
      ..write(maskedSpoken(context, spokenMoney(t.amount)))
      ..write(', $title, $day');
    if (note != null) spoken.write(', комментарий: $note');
    return OperationTile(
      key: ValueKey('category-operation-${t.id}'),
      title: title,
      subtitle: note == null ? day : '$day · $note',
      amount: t.amount,
      isIncome: isIncome,
      iconKey: subId == null
          ? widget.category.iconKey
          : icons[subId] ?? widget.category.iconKey,
      categoryName: subId == null
          ? widget.category.name
          : names[subId] ?? widget.category.name,
      semanticLabel: spoken.toString(),
      onTap: onOpen == null ? null : () => onOpen(t),
      horizontalPadding: 0,
    );
  }

  Widget _totalCenter(ThemeData theme, String text, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Всего',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        MaskedAmount(
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
        MaskedAmount(
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
    required this.iconKey,
    required this.avatarName,
    required this.amount,
    required this.isExpense,
    required this.amountColor,
    required this.share,
    required this.color,
  });

  final String label;
  final String? iconKey;

  /// Название для буквы в аватаре (ключ «Другое»).
  final String? avatarName;
  final Money amount;
  final bool isExpense;
  final Color amountColor;
  final PercentShare share;
  final Color color;

  /// Сумма со знаком типа: «−…» для расхода, «+…» для дохода.
  String get signedAmount =>
      isExpense ? '−${formatMoney(amount)}' : '+${formatMoney(amount)}';

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
      label:
          '${row.label}, ${row.isExpense ? 'расход' : 'доход'} '
          '${maskedSpoken(context, spokenMoney(row.amount))}, '
          '${row.percentSpoken}',
      excludeSemantics: true,
      child: CategoryStatLine(
        leading: CategoryAvatar(
          row.iconKey,
          name: row.avatarName,
          color: row.color,
        ),
        name: row.label,
        amount: MaskedAmount(
          row.signedAmount,
          style: categoryAmountStyle(theme, color: row.amountColor),
        ),
        subtitle: Text(row.percentText, style: categorySubtitleStyle(theme)),
      ),
    );
  }
}
