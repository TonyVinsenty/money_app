import 'package:flutter/material.dart';
import 'package:money_app/core/format/period_label.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/async_view.dart';
import 'package:money_app/core/ui/bottom_inset.dart';
import 'package:money_app/core/ui/date_wheel_sheet.dart';
import 'package:money_app/core/ui/other_currencies_hint.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/domain/period_summary.dart';
import 'package:money_app/features/analytics/presentation/analytics_controller.dart';
import 'package:money_app/features/analytics/presentation/analytics_hints_card.dart';
import 'package:money_app/features/analytics/presentation/analytics_texts.dart';
import 'package:money_app/features/analytics/presentation/category_breakdown_card.dart';
import 'package:money_app/features/analytics/presentation/comparison_section.dart';
import 'package:money_app/features/analytics/presentation/dynamics_section.dart';
import 'package:money_app/features/analytics/presentation/operations_section.dart';
import 'package:money_app/features/analytics/presentation/period_header.dart';
import 'package:money_app/features/analytics/presentation/period_summary_card.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Операции вместе с периодом, для которого их запросили. Пока после смены
/// периода не пришёл новый ответ, на экране остаются прежние операции, и итог
/// считается по прежнему периоду, а не по новому (иначе мигало бы «пусто»).
///
/// В [transactions] лежит окно данных: операции периода [range] и периода
/// сравнения [previousRange] (ADR 0012, п. 2). «Категории» и «пусто» считают
/// только [range].
typedef PeriodTransactions = ({
  DateRange range,
  DateRange previousRange,
  List<Transaction> transactions,
});

/// Ключ скелетона до первого ответа базы.
const Key analyticsSkeletonKey = ValueKey('analytics-skeleton');

/// Ключ раздела «Сравнение».
const Key analyticsComparisonKey = ValueKey('analytics-comparison');

/// Ключ раздела «Динамика».
const Key analyticsDynamicsKey = ValueKey('analytics-dynamics');

/// Ключ раздела «Операции».
const Key analyticsOperationsKey = ValueKey('analytics-operations');

/// Ключ строки разделов.
const Key analyticsSectionBarKey = ValueKey('analytics-section-bar');

/// Разделы, которые уже есть на экране, слева направо. Остальные добавят
/// свои шаги (ROADMAP, a.4).
const List<AnalyticsSection> _shownSections = [
  AnalyticsSection.categories,
  AnalyticsSection.dynamics,
  AnalyticsSection.comparison,
  AnalyticsSection.operations,
];

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
    this.onOpenTransaction,
    this.dynamicsCategoryId,
    this.onDynamicsCategorySelected,
    this.section = AnalyticsSection.categories,
    this.onSectionSelected,
    this.firstDay,
    this.firstDayKnown = false,
    this.onCustomRangeSelected,
    this.currency = rubCurrencyCode,
    this.hasOtherCurrencies,
    this.currencySymbol = '₽',
    this.onAddExpense,
    super.key,
  });

  /// «Добавить расход» в пустой «Аналитике»: куда ведёт, решает приложение
  /// (быстрый ввод); без колбэка кнопки нет.
  final VoidCallback? onAddExpense;

  /// Есть ли операции в других валютах (подсказка в пустом периоде);
  /// `null` — подсказки нет.
  final Stream<bool>? hasOtherCurrencies;

  /// Знак основной валюты для подсказки.
  final String currencySymbol;

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

  /// Выбрана операция в «Крупных» (правка открывается из `lib/app/`); без
  /// колбэка строки не кнопки.
  final ValueChanged<Transaction>? onOpenTransaction;

  /// Категория, выбранная фильтром «Динамики»; `null` — все категории.
  final String? dynamicsCategoryId;

  /// Выбрана категория фильтра «Динамики» (`null` — все); без колбэка чипа
  /// фильтра нет.
  final ValueChanged<String?>? onDynamicsCategorySelected;

  /// Раздел, содержимое которого показано под выбором периода. Раздел, которого
  /// на экране ещё нет, показывается как «Категории».
  final AnalyticsSection section;

  /// Выбран другой раздел касанием строки разделов; без колбэка строка
  /// не реагирует на касания.
  final ValueChanged<AnalyticsSection>? onSectionSelected;

  /// Стандартный выбор интервала. Последний день — сегодня, первый — день
  /// первой операции (без операций — сегодня). Отмена ничего не меняет.
  Future<void> _pickCustomRange(BuildContext context) async {
    final first = firstDay != null && firstDay! <= today ? firstDay! : today;
    DateOnly clamp(DateOnly day) => day < first
        ? first
        : day > today
        ? today
        : day;
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      // iPhone: два шага с колесом «С…» / «По…»; «По» не раньше «С».
      final start = await pickDate(
        context,
        initial: clamp(period.range.start),
        first: first,
        last: today,
        today: today,
        title: 'С какого дня',
      );
      if (start == null || !context.mounted) return;
      final end = await pickDate(
        context,
        initial: clamp(period.range.end) < start
            ? start
            : clamp(period.range.end),
        first: start,
        last: today,
        today: today,
        title: 'По какой день',
      );
      if (end == null) return;
      onCustomRangeSelected?.call(start, end);
      return;
    }
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
      padding: withBottomInset(context, const EdgeInsets.all(AppSpacing.l)),
      children: [
        _SectionBar(section: section, onSelected: onSectionSelected),
        const SizedBox(height: AppSpacing.s),
        PeriodHeader(
          kind: period.kind,
          label: formatPeriodLabel(period.kind, period.range, today: today),
          onKindSelected: onKindSelected,
          onCustomSelected: onCustomRangeSelected == null
              ? null
              : () => _pickCustomRange(context),
          onPrevious: onPrevious,
          onNext: onNext,
          previousTooltip: previousTooltip,
          nextTooltip: nextTooltip,
        ),
        const SizedBox(height: AppSpacing.l),
        AsyncView<PeriodTransactions>(
          // Ключ по валюте: при смене основной валюты прежние данные (в старой
          // валюте) выбрасываются, и до ответа нового потока виден скелетон.
          key: ValueKey('analytics-data-$currency'),
          stream: transactions,
          loadingBuilder: (_) => const _SummarySkeleton(),
          errorBuilder: (context, error) => const _SummaryError(),
          isEmpty: (data) =>
              !data.transactions.any((t) => data.range.contains(t.occurredOn)),
          emptyBuilder: (_) => _EmptyPeriod(
            noOperationsAtAll: firstDayKnown && firstDay == null,
            hasOtherCurrencies: hasOtherCurrencies,
            symbol: currencySymbol,
            onAddExpense: onAddExpense,
          ),
          dataBuilder: (context, data) => section == AnalyticsSection.dynamics
              ? AsyncView<List<Category>>(
                  stream: categories,
                  errorBuilder: (context, error) => const _SummaryError(),
                  dataBuilder: (context, all) => DynamicsSection(
                    key: analyticsDynamicsKey,
                    transactions: data.transactions,
                    period: AnalyticsPeriod(period.kind, data.range),
                    today: today,
                    type: type,
                    currency: currency,
                    onTypeSelected: onTypeSelected,
                    categories: all,
                    categoryId: dynamicsCategoryId,
                    onCategorySelected: onDynamicsCategorySelected,
                  ),
                )
              : section == AnalyticsSection.operations
              ? AsyncView<List<Category>>(
                  stream: categories,
                  errorBuilder: (context, error) => const _SummaryError(),
                  dataBuilder: (context, all) => OperationsSection(
                    key: analyticsOperationsKey,
                    transactions: data.transactions,
                    range: data.range,
                    categories: all,
                    today: today,
                    type: type,
                    currency: currency,
                    onTypeSelected: onTypeSelected,
                    onOpenTransaction: onOpenTransaction,
                    onOpenCategory: onOpenCategory,
                  ),
                )
              : section == AnalyticsSection.comparison
              ? AsyncView<List<Category>>(
                  stream: categories,
                  errorBuilder: (context, error) => const _SummaryError(),
                  dataBuilder: (context, all) => ComparisonSection(
                    key: analyticsComparisonKey,
                    transactions: data.transactions,
                    range: data.range,
                    previousRange: data.previousRange,
                    categories: all,
                    today: today,
                    type: type,
                    currency: currency,
                    onTypeSelected: onTypeSelected,
                    onOpenCategory: onOpenCategory,
                  ),
                )
              : Column(
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
                      dataBuilder: (context, all) => Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AnalyticsHintsCard(
                            transactions: data.transactions,
                            period: AnalyticsPeriod(period.kind, data.range),
                            today: today,
                            categories: all,
                            currency: currency,
                          ),
                          CategoryBreakdownCard(
                            currency: currency,
                            transactions: data.transactions,
                            range: data.range,
                            categories: all,
                            type: type,
                            onTypeSelected: onTypeSelected,
                            onOpenCategory: onOpenCategory,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Строка разделов: прокручиваемый `TabBar` (при крупном шрифте уходит вбок, а
/// не обрезается). Содержимое меняется только касанием, свайпа между
/// разделами нет (ADR 0012, п. 1): палец на кольце и столбиках двигается вбок.
class _SectionBar extends StatefulWidget {
  const _SectionBar({required this.section, required this.onSelected});

  final AnalyticsSection section;
  final ValueChanged<AnalyticsSection>? onSelected;

  @override
  State<_SectionBar> createState() => _SectionBarState();
}

class _SectionBarState extends State<_SectionBar>
    with SingleTickerProviderStateMixin {
  late final TabController _controller = TabController(
    length: _shownSections.length,
    vsync: this,
    initialIndex: _indexOf(widget.section),
  );

  static int _indexOf(AnalyticsSection section) {
    final index = _shownSections.indexOf(section);
    return index < 0 ? 0 : index;
  }

  @override
  void didUpdateWidget(_SectionBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final index = _indexOf(widget.section);
    if (_controller.index != index) _controller.index = index;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSelected = widget.onSelected;
    // Без колбэка строка не реагирует на касания (сам TabBar переключил бы
    // вкладку и без onTap), поэтому касания выключены целиком.
    final style =
        Theme.of(context).tabBarTheme.labelStyle ??
        Theme.of(context).textTheme.titleSmall ??
        const TextStyle(fontSize: 14);
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    // Ширина самой длинной подписи с учётом масштаба шрифта.
    var longest = 0.0;
    for (final section in _shownSections) {
      final painter = TextPainter(
        text: TextSpan(text: analyticsSectionTitle(section), style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      if (painter.width > longest) longest = painter.width;
      painter.dispose();
    }
    return IgnorePointer(
      ignoring: onSelected == null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Поровну: четыре раздела по четверти ширины, если подписи влезают.
          final fits =
              longest + 2 * _tabPadding + 1 <=
              constraints.maxWidth / _shownSections.length;
          return TabBar(
            key: analyticsSectionBarKey,
            controller: _controller,
            isScrollable: !fits,
            tabAlignment: fits ? TabAlignment.fill : TabAlignment.start,
            labelPadding: EdgeInsets.symmetric(
              horizontal: fits ? _tabPadding : _scrollTabPadding,
            ),
            // Справа запас: край следующего раздела виден, что есть куда листать.
            padding: fits ? null : const EdgeInsets.only(right: 24),
            onTap: onSelected == null
                ? null
                : (index) => onSelected(_shownSections[index]),
            tabs: [
              for (final section in _shownSections)
                Tab(text: analyticsSectionTitle(section)),
            ],
          );
        },
      ),
    );
  }

  static const double _tabPadding = 2;
  static const double _scrollTabPadding = 12;
}

class _EmptyPeriod extends StatelessWidget {
  const _EmptyPeriod({
    required this.noOperationsAtAll,
    required this.hasOtherCurrencies,
    required this.symbol,
    required this.onAddExpense,
  });

  /// Кнопка «Добавить расход» при пустой базе; `null` — кнопки нет.
  final VoidCallback? onAddExpense;

  /// Операций нет вообще (а не только в этом периоде).
  final bool noOperationsAtAll;
  final Stream<bool>? hasOtherCurrencies;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final add = onAddExpense;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.bar_chart_rounded, size: 48, color: muted),
          const SizedBox(height: AppSpacing.m),
          Text(
            noOperationsAtAll
                ? 'Операций пока нет. Добавьте первую — и здесь появится статистика'
                : 'За этот период операций нет',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(color: muted),
          ),
          if (!noOperationsAtAll) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              'Выберите другой период стрелками вверху',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            ),
          ] else if (add != null) ...[
            const SizedBox(height: AppSpacing.l),
            FilledButton.icon(
              onPressed: add,
              icon: const Icon(Icons.add),
              label: const Text('Добавить расход'),
            ),
          ],
          OtherCurrenciesHint(hasOther: hasOtherCurrencies, symbol: symbol),
        ],
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
      decoration: BoxDecoration(color: color, borderRadius: AppRadius.borderM),
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
