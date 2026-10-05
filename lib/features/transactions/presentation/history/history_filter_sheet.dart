import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/history_view.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';

/// Открывает лист фильтра «Истории».
///
/// Лист — отдельный маршрут, поэтому он получает не снимок фильтра, а
/// [filter] (за ним следит лист) и [onChanged] (изменения применяются сразу,
/// список под листом меняется на глазах). Закрывается «Готово», жестом «Назад»
/// или смахиванием вниз.
Future<void> showHistoryFilterSheet(
  BuildContext context, {
  required ValueListenable<HistoryFilter> filter,
  required ValueChanged<HistoryFilter> onChanged,
  List<Category> categories = const [],
  List<Transaction> monthTransactions = const [],
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => HistoryFilterSheet(
      filter: filter,
      onChanged: onChanged,
      categories: categories,
      monthTransactions: monthTransactions,
    ),
  );
}

/// Раздел категорий одного вида: «Выбрать все» / «Снять все» и галочки.
/// [selected] — набор фильтра (`null` — все); [onSelected] получает новый.
class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.title,
    required this.kind,
    required this.categories,
    required this.monthTransactions,
    required this.selected,
    required this.onSelected,
  });

  final String title;
  final CategoryKind kind;
  final List<Category> categories;
  final List<Transaction> monthTransactions;
  final Set<String>? selected;
  final ValueChanged<Set<String>?> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = historyFilterCategories(
      categories: categories,
      kind: kind,
      monthTransactions: monthTransactions,
      selected: selected,
    );
    final visibleIds = {for (final c in visible) c.id};
    void toggle(String id, bool checked) {
      final next = {...(selected ?? visibleIds)};
      checked ? next.add(id) : next.remove(id);
      // Все отмечены — ограничения по категориям нет.
      onSelected(next.containsAll(visibleIds) ? null : next);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text(title, style: theme.textTheme.titleMedium),
        ),
        // Wrap: при крупном шрифте кнопки переносятся, а не вылезают за край.
        Wrap(
          alignment: WrapAlignment.end,
          children: [
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => onSelected(null),
              child: const Text('Выбрать все'),
            ),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => onSelected(<String>{}),
              child: const Text('Снять все'),
            ),
          ],
        ),
        if (selected != null && selected!.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'Не выбрана ни одна категория',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final c in visible)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(c.name),
            value: selected == null || selected!.contains(c.id),
            onChanged: (v) => toggle(c.id, v ?? false),
          ),
      ],
    );
  }
}

/// Содержимое листа фильтра: заголовок, «Сбросить», тип, разделы категорий,
/// «Готово». [categories] и [monthTransactions] (операции показанного месяца)
/// нужны, чтобы решить, какие категории показать.
class HistoryFilterSheet extends StatelessWidget {
  const HistoryFilterSheet({
    required this.filter,
    required this.onChanged,
    this.categories = const [],
    this.monthTransactions = const [],
    super.key,
  });

  final ValueListenable<HistoryFilter> filter;
  final ValueChanged<HistoryFilter> onChanged;
  final List<Category> categories;
  final List<Transaction> monthTransactions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Прокрутка: при крупном шрифте содержимое не помещается в лист.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: ValueListenableBuilder<HistoryFilter>(
        valueListenable: filter,
        builder: (context, current, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text('Фильтр', style: theme.textTheme.titleLarge),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: current.isActive
                      ? () => onChanged(HistoryFilter.off)
                      : null,
                  child: const Text('Сбросить'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<HistoryTypeFilter>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: HistoryTypeFilter.all, label: Text('Все')),
                ButtonSegment(
                  value: HistoryTypeFilter.income,
                  label: Text('Доходы'),
                ),
                ButtonSegment(
                  value: HistoryTypeFilter.expense,
                  label: Text('Расходы'),
                ),
              ],
              selected: {current.type},
              // Наборы категорий сохраняются: меняется только тип.
              onSelectionChanged: (selection) => onChanged(
                HistoryFilter(
                  type: selection.first,
                  expenseCategoryIds: current.expenseCategoryIds,
                  incomeCategoryIds: current.incomeCategoryIds,
                ),
              ),
            ),
            if (current.type != HistoryTypeFilter.income)
              _CategorySection(
                title: 'Категории расходов',
                kind: CategoryKind.expense,
                categories: categories,
                monthTransactions: monthTransactions,
                selected: current.expenseCategoryIds,
                onSelected: (ids) => onChanged(
                  HistoryFilter(
                    type: current.type,
                    expenseCategoryIds: ids,
                    incomeCategoryIds: current.incomeCategoryIds,
                  ),
                ),
              ),
            if (current.type != HistoryTypeFilter.expense)
              _CategorySection(
                title: 'Категории доходов',
                kind: CategoryKind.income,
                categories: categories,
                monthTransactions: monthTransactions,
                selected: current.incomeCategoryIds,
                onSelected: (ids) => onChanged(
                  HistoryFilter(
                    type: current.type,
                    expenseCategoryIds: current.expenseCategoryIds,
                    incomeCategoryIds: ids,
                  ),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Готово'),
            ),
          ],
        ),
      ),
    );
  }
}
