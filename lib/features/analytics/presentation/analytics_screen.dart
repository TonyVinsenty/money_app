import 'package:flutter/material.dart';
import 'package:money_app/core/format/period_label.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/async_view.dart';
import 'package:money_app/core/ui/period_switcher.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/domain/period_summary.dart';
import 'package:money_app/features/analytics/presentation/category_breakdown_card.dart';
import 'package:money_app/features/analytics/presentation/period_summary_card.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Операции вместе с периодом, для которого их запросили. Пока после смены
/// периода не пришёл новый ответ, на экране остаются прежние операции, и итог
/// считается по прежнему периоду, а не по новому (иначе мигало бы «пусто»).
typedef PeriodTransactions = ({
  DateRange range,
  List<Transaction> transactions,
});

/// Ключ скелетона до первого ответа базы.
const Key analyticsSkeletonKey = ValueKey('analytics-skeleton');

/// Виды периода, которые можно выбрать чипом, в порядке слева направо.
const List<(PeriodKind, String)> _kindChips = [
  (PeriodKind.day, 'День'),
  (PeriodKind.week, 'Неделя'),
  (PeriodKind.month, 'Месяц'),
  (PeriodKind.year, 'Год'),
];

/// Поля чипа уже стандартных, чтобы пять чипов встали в одну строку на 360 dp.
/// Высота зоны нажатия (48 dp) от полей не зависит.
const EdgeInsets _chipPadding = EdgeInsets.symmetric(horizontal: 4);
const EdgeInsets _chipLabelPadding = EdgeInsets.symmetric(horizontal: 4);

/// Подсказки стрелок по виду периода: (назад, вперёд).
(String, String) _arrowTooltips(PeriodKind kind) => switch (kind) {
  PeriodKind.day => ('Предыдущий день', 'Следующий день'),
  PeriodKind.week => ('Предыдущая неделя', 'Следующая неделя'),
  PeriodKind.month => ('Предыдущий месяц', 'Следующий месяц'),
  PeriodKind.year => ('Предыдущий год', 'Следующий год'),
  PeriodKind.custom => ('Предыдущий период', 'Следующий период'),
};

/// Экран «Аналитика»: выбор вида периода и переключатель периода; под ними
/// место для итогов.
///
/// Экран ничего не знает ни о выбранном периоде как состоянии, ни о
/// репозиториях, ни о маршрутах (ADR 0002): всё приходит параметрами.
/// [onPrevious] или [onNext] равный `null` значит «стрелка недоступна».
class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({
    required this.period,
    required this.today,
    required this.onKindSelected,
    required this.onPrevious,
    required this.onNext,
    required this.transactions,
    required this.categories,
    this.type = TransactionType.expense,
    this.onTypeSelected,
    this.onOpenCategory,
    this.firstDay,
    this.firstDayKnown = false,
    this.onCustomRangeSelected,
    this.currency = rubCurrencyCode,
    super.key,
  });

  /// Код основной валюты: в ней считаются итоги и разбивка по категориям.
  final String currency;

  final AnalyticsPeriod period;
  final DateOnly today;
  final ValueChanged<PeriodKind> onKindSelected;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// Операции выбранного периода. Поток один и тот же между перерисовками;
  /// новый создаётся только при смене периода.
  final Stream<PeriodTransactions> transactions;

  /// Все категории, включая архивные (для названий в разбивке по категориям).
  final Stream<List<Category>> categories;

  /// День первой операции: раньше него в выборе своего интервала выбрать
  /// нельзя. `null` — операций нет или ещё неизвестно.
  final DateOnly? firstDay;

  /// База уже ответила про первую операцию. Пока нет, null в [firstDay] не
  /// значит «операций нет вообще».
  final bool firstDayKnown;

  /// Свой интервал выбран в диалоге (начало, конец включительно). Без колбэка
  /// чип «Свой» недоступен.
  final void Function(DateOnly start, DateOnly end)? onCustomRangeSelected;

  /// Какие операции показывают кольцо и список: расходы или доходы.
  final TransactionType type;

  /// Выбран другой тип в переключателе; без колбэка переключатель недоступен.
  final ValueChanged<TransactionType>? onTypeSelected;

  /// Выбрана категория (строка списка или сектор кольца). Маршрут открывает
  /// вызывающий; без колбэка строки не кнопки.
  final ValueChanged<Category>? onOpenCategory;

  /// Стандартный выбор интервала. Последний день — сегодня, первый — день
  /// первой операции (без операций — сегодня). Отмена ничего не меняет.
  Future<void> _pickCustomRange(BuildContext context) async {
    final first = firstDay != null && firstDay! <= today ? firstDay! : today;
    DateOnly clamp(DateOnly day) => day < first
        ? first
        : day > today
        ? today
        : day;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: first.toDateTime(),
      lastDate: today.toDateTime(),
      initialDateRange: DateTimeRange(
        start: clamp(period.range.start).toDateTime(),
        end: clamp(period.range.end).toDateTime(),
      ),
    );
    if (picked == null) return;
    onCustomRangeSelected?.call(
      DateOnly.fromDateTime(picked.start),
      DateOnly.fromDateTime(picked.end),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (previousTooltip, nextTooltip) = _arrowTooltips(period.kind);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final (kind, label) in _kindChips)
              ChoiceChip(
                label: Text(label),
                showCheckmark: false,
                padding: _chipPadding,
                labelPadding: _chipLabelPadding,
                selected: period.kind == kind,
                onSelected: (_) => onKindSelected(kind),
              ),
            ChoiceChip(
              label: const Text('Свой'),
              showCheckmark: false,
              padding: _chipPadding,
              labelPadding: _chipLabelPadding,
              selected: period.kind == PeriodKind.custom,
              onSelected: onCustomRangeSelected == null
                  ? null
                  : (_) => _pickCustomRange(context),
            ),
          ],
        ),
        const SizedBox(height: 8),
        PeriodSwitcher(
          label: formatPeriodLabel(period.kind, period.range, today: today),
          onPrevious: onPrevious,
          onNext: onNext,
          previousTooltip: previousTooltip,
          nextTooltip: nextTooltip,
        ),
        const SizedBox(height: 16),
        AsyncView<PeriodTransactions>(
          stream: transactions,
          loadingBuilder: (_) => const _SummarySkeleton(),
          errorBuilder: (context, error) => const _SummaryError(),
          isEmpty: (data) => data.transactions.isEmpty,
          emptyBuilder: (_) => _EmptyPeriod(
            noOperationsAtAll: firstDayKnown && firstDay == null,
          ),
          dataBuilder: (context, data) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PeriodSummaryCard(
                summary: summarizePeriod(
                  data.transactions,
                  data.range,
                  currency: currency,
                ),
              ),
              const SizedBox(height: 16),
              AsyncView<List<Category>>(
                stream: categories,
                errorBuilder: (context, error) => const _SummaryError(),
                dataBuilder: (context, all) => CategoryBreakdownCard(
                  currency: currency,
                  transactions: data.transactions,
                  range: data.range,
                  categories: all,
                  type: type,
                  onTypeSelected: onTypeSelected,
                  onOpenCategory: onOpenCategory,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmptyPeriod extends StatelessWidget {
  const _EmptyPeriod({required this.noOperationsAtAll});

  /// Операций нет вообще (а не только в этом периоде).
  final bool noOperationsAtAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        noOperationsAtAll
            ? 'Операций пока нет. Добавьте первую — и здесь появится статистика'
            : 'За этот период операций нет',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SummaryError extends StatelessWidget {
  const _SummaryError();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.error_outline, color: scheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Не удалось посчитать итоги за период',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// Серые полоски на месте будущей карточки (без анимации). Скринридеру —
/// одна подпись «Загрузка».
class _SummarySkeleton extends StatelessWidget {
  const _SummarySkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bar(double width) => Container(
      width: width,
      height: 20,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );
    return Semantics(
      label: 'Загрузка итогов',
      child: ExcludeSemantics(
        child: Column(
          key: analyticsSkeletonKey,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < 3; i++) ...[
              bar(i == 0 ? 160 : 120),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}
