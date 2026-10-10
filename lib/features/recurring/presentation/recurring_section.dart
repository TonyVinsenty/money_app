import 'package:flutter/material.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/async_view.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/domain/recurring_repository.dart';
import 'package:money_app/features/recurring/domain/recurring_schedule.dart';
import 'package:money_app/features/recurring/presentation/recurring_texts.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Раздел «Регулярные платежи» вкладки «Баланс» (ADR 0011).
///
/// Поток приносит вызывающий (`lib/app`, ADR 0002) и держит его одним и тем же
/// между перерисовками. «Следующий платёж» считается здесь от [today], а не
/// берётся из потока: поток обновляется только при записи в базу, а день
/// может смениться и без неё. Закончившиеся платежи идут в конце.
class RecurringSection extends StatelessWidget {
  const RecurringSection({
    required this.items,
    required this.today,
    required this.onAdd,
    super.key,
  });

  final Stream<List<RecurringListItem>> items;

  /// Сегодняшний день; при его смене раздел пересчитывает «следующий».
  final DateOnly today;

  /// Нажатие «Добавить платёж».
  final VoidCallback onAdd;

  static const addButtonKey = ValueKey('recurring-add');
  static const emptyKey = ValueKey('recurring-empty');
  static ValueKey<String> rowKey(String id) => ValueKey('recurring-row-$id');
  static ValueKey<String> nextKey(String id) => ValueKey('recurring-sub-$id');

  /// Платежи с «следующим» на день [today]: по ближайшей дате, закончившиеся
  /// в конце, затем по названию и `id` (как в репозитории).
  static List<(RecurringPayment, DateOnly?)> arranged(
    List<RecurringListItem> items,
    DateOnly today,
  ) {
    final rows = [
      for (final i in items)
        (i.payment, nextDueAfter(i.payment, today.addDays(-1))),
    ];
    rows.sort((a, b) {
      final da = a.$2;
      final db = b.$2;
      if (da != db) {
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      }
      final byTitle = a.$1.title.toLowerCase().compareTo(
        b.$1.title.toLowerCase(),
      );
      return byTitle != 0 ? byTitle : a.$1.id.compareTo(b.$1.id);
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              recurringSectionTitle,
              style: theme.textTheme.titleMedium,
            ),
          ),
        ),
        AsyncView<List<RecurringListItem>>(
          stream: items,
          loadingBuilder: (_) => const AsyncLoading(),
          errorBuilder: (context, error) => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(AsyncView.defaultErrorText),
          ),
          isEmpty: (all) => all.isEmpty,
          emptyBuilder: (context) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              recurringEmptyText,
              key: emptyKey,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          dataBuilder: (context, all) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (payment, next) in arranged(all, today))
                _Row(payment, next),
            ],
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          key: addButtonKey,
          style: ButtonStyle(
            minimumSize: WidgetStateProperty.all(const Size(0, 48)),
          ),
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text(recurringAddButton),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.payment, this.next);

  final RecurringPayment payment;
  final DateOnly? next;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final isIncome = payment.type == TransactionType.income;
    return Semantics(
      container: true,
      label: recurringRowSemantics(payment, next),
      excludeSemantics: true,
      child: ConstrainedBox(
        key: RecurringSection.rowKey(payment.id),
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      payment.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge,
                    ),
                    Text(
                      recurringSubtitleText(payment, next),
                      key: RecurringSection.nextKey(payment.id),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Сумма не переносится; совсем длинная сжимается до 45 % ширины.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.45,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    recurringAmountText(payment),
                    softWrap: false,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: isIncome ? colors.income : colors.expense,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
