import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:money_app/features/transactions/domain/history_view.dart';

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
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) =>
        HistoryFilterSheet(filter: filter, onChanged: onChanged),
  );
}

/// Содержимое листа фильтра: заголовок, «Сбросить», тип, «Готово».
/// Шаг 4.22 добавит под типом разделы категорий.
class HistoryFilterSheet extends StatelessWidget {
  const HistoryFilterSheet({
    required this.filter,
    required this.onChanged,
    super.key,
  });

  final ValueListenable<HistoryFilter> filter;
  final ValueChanged<HistoryFilter> onChanged;

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
