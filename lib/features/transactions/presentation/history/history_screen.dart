import 'dart:async';

import 'package:flutter/material.dart';
import 'package:money_app/core/format/date_format.dart';
import 'package:money_app/core/format/day_label.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/format/percent_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/async_view.dart';
import 'package:money_app/core/ui/category_icon_view.dart';
import 'package:money_app/core/ui/category_labels.dart';
import 'package:money_app/core/ui/other_currencies_hint.dart';
import 'package:money_app/core/ui/period_switcher.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/analytics/domain/period_summary.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/history_view.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/history/history_filter_label.dart';
import 'package:money_app/features/transactions/presentation/history/history_filter_sheet.dart';

/// Настоящий минус (U+2212), а не дефис (как в `AmountField`).
final String _minusSign = String.fromCharCode(0x2212);

/// Ключ заглушки-скелетона: по нему тесты отличают «ещё грузится» от «пусто».
const Key historySkeletonKey = ValueKey('history-skeleton');

/// Вкладка «История»: живые операции по дням, новые сверху.
///
/// Экран не знает, откуда берутся данные и куда ведёт нажатие: потоки и
/// [onTransactionTap] передаёт приложение (`lib/app`), поэтому фича не зависит
/// от маршрутов и хранилища (ADR 0002). Потоки должны быть одними и теми же
/// между перерисовками (их создаёт вызывающий), иначе подписка начнётся заново.
///
/// - [transactions] — операции уже в нужном порядке (новые сверху): экран лишь
///   группирует подряд идущие операции одного дня под заголовком;
/// - [categories] — справочник с архивными категориями и подкатегориями:
///   из него берутся имя и иконка. Операция по архивной категории показывает
///   её имя; если категории нет вовсе — «Без категории».
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    required this.transactions,
    required this.categories,
    required this.today,
    required this.month,
    required this.hasAnyTransactions,
    required this.onTransactionTap,
    this.onPreviousMonth,
    this.onNextMonth,
    this.filter = HistoryFilter.off,
    this.sort = HistorySort.newestFirst,
    this.onResetFilter,
    this.onSortChanged,
    this.onFilterChanged,
    this.searchQuery = '',
    this.onSearchChanged,
    this.hasOtherCurrencies,
    this.currencySymbol = '₽',
    this.currencyCode = 'RUB',
    this.accounts,
    super.key,
  });

  /// Счета (для имени в полоске фильтра по счёту); тот же поток между
  /// перерисовками. Без него неизвестный счёт подписывается запасным текстом.
  final Stream<List<Account>>? accounts;

  /// Есть ли операции в других валютах (пустой месяц объясняет, почему их не
  /// видно). `null` — подсказки нет.
  final Stream<bool>? hasOtherCurrencies;

  /// Знак основной валюты для подсказки.
  final String currencySymbol;

  /// Код основной валюты: в листе фильтра предлагаются только её счета.
  final String currencyCode;

  /// Текст поиска как набран. Непустой (не из одних пробелов) — режим поиска:
  /// [transactions] тогда отдаёт операции всех месяцев, а экран оставляет те,
  /// где запрос входит в комментарий или имя подкатегории.
  final String searchQuery;

  /// Изменение текста в поле поиска; `null` — поля нет.
  final ValueChanged<String>? onSearchChanged;

  /// Изменения фильтра из листа; `null` — кнопка «Фильтр» недоступна.
  final ValueChanged<HistoryFilter>? onFilterChanged;

  /// Выбор порядка в меню; `null` — меню недоступно.
  final ValueChanged<HistorySort>? onSortChanged;

  /// Фильтр и порядок: экран применяет их к пришедшему [transactions].
  final HistoryFilter filter;
  final HistorySort sort;

  /// Кнопки «Сбросить» (полоска фильтра и пустой результат).
  final VoidCallback? onResetFilter;

  final Stream<List<Transaction>> transactions;
  final Stream<List<Category>> categories;

  /// Сегодняшний день: от него считаются «Сегодня» и «Вчера» в заголовках.
  final DateOnly today;

  /// Любой день показываемого месяца: из него берётся подпись переключателя.
  /// [transactions] должен отдавать операции именно этого месяца.
  final DateOnly month;

  /// Есть ли в базе хоть одна операция (в любом месяце): от этого зависит
  /// текст пустого состояния. `null` — ещё неизвестно (база не ответила):
  /// пустой месяц тогда показывает загрузку, а не «Операций пока нет».
  final bool? hasAnyTransactions;

  /// Тап по строке. Правку по нему подключает шаг 2.28.
  final ValueChanged<Transaction> onTransactionTap;

  /// Стрелки переключателя месяца; `null` — стрелка недоступна.
  final VoidCallback? onPreviousMonth;
  final VoidCallback? onNextMonth;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

/// Операции вместе с месяцем, для которого их запрашивали: при смене месяца на
/// экране остаются прежние операции, пока не придут новые, и текст пустого
/// состояния должен называть тот месяц, которому принадлежат данные.
typedef _MonthData = ({DateOnly month, List<Transaction> transactions});

class _HistoryScreenState extends State<HistoryScreen> {
  late Stream<_MonthData> _data = _tag();

  /// Текущий фильтр для открытого листа (он отдельный маршрут и сам не
  /// перестраивается от смены виджета).
  late final ValueNotifier<HistoryFilter> _filter = ValueNotifier(
    widget.filter,
  );

  /// Текст поля поиска; источник истины — [HistoryScreen.searchQuery].
  late final TextEditingController _search = TextEditingController(
    text: widget.searchQuery,
  );

  bool get _searching => normalizeHistorySearch(widget.searchQuery).isNotEmpty;

  void _clearSearch() {
    _search.clear();
    widget.onSearchChanged?.call('');
  }

  // Имена счетов для полоски «Счёт: Карта» (архивные тоже).
  Map<String, String> _accountNames = const {};
  List<Account> _accountList = const [];
  StreamSubscription<List<Account>>? _accountsSub;

  String? get _filterAccountName => _accountNames[widget.filter.accountId];

  void _listenAccounts() {
    unawaited(_accountsSub?.cancel());
    _accountsSub = widget.accounts?.listen(
      (all) {
        if (mounted) {
          setState(() {
            _accountList = all;
            _accountNames = {for (final a in all) a.id: a.name};
          });
        }
      },
      onError: (Object error) {
        debugPrint('Не удалось загрузить имена счетов: $error');
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _listenAccounts();
  }

  @override
  void dispose() {
    unawaited(_accountsSub?.cancel());
    _filter.dispose();
    _search.dispose();
    super.dispose();
  }

  void _openFilter() {
    final onChanged = widget.onFilterChanged;
    if (onChanged == null) return;
    showHistoryFilterSheet(
      context,
      filter: _filter,
      onChanged: onChanged,
      categories: _allCategories,
      monthTransactions: _monthTransactions,
      accounts: [
        for (final a in _accountList)
          if (a.currency == widget.currencyCode) a,
      ],
    );
  }

  // Последние данные экрана: лист берёт их при открытии, без новых запросов.
  List<Category> _allCategories = const [];
  List<Transaction> _monthTransactions = const [];

  Stream<_MonthData> _tag() {
    final month = widget.month;
    return widget.transactions.map(
      (transactions) => (month: month, transactions: transactions),
    );
  }

  @override
  void didUpdateWidget(HistoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Лист слушает notifier, а менять его прямо в build нельзя: после кадра.
    if (_filter.value != widget.filter) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _filter.value = widget.filter;
      });
    }
    if (!identical(oldWidget.transactions, widget.transactions)) {
      _data = _tag();
    }
    if (!identical(oldWidget.accounts, widget.accounts)) _listenAccounts();
    // Запрос сменили снаружи (кнопка «Очистить поиск»): поле догоняет.
    if (_search.text != widget.searchQuery) {
      _search.value = TextEditingValue(
        text: widget.searchQuery,
        selection: TextSelection.collapsed(offset: widget.searchQuery.length),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Справочник снаружи, операции внутри: справочник живёт, пока открыта
    // вкладка, а пустое состояние показывается только после ответа базы (до
    // него — скелетон, а не «Операций пока нет»).
    final body = AsyncView<List<Category>>(
      stream: widget.categories,
      loadingBuilder: (_) => const _HistorySkeleton(),
      dataBuilder: (context, all) {
        final byId = {for (final c in all) c.id: c};
        final list = AsyncView<_MonthData>(
          stream: _data,
          loadingBuilder: (_) => const _HistorySkeleton(),
          // Пустоту разбираем сами: тексту нужен месяц данных (не выбранный),
          // без мелькания чужого названия.
          dataBuilder: (context, data) {
            // Над списком строка «Фильтр» + порядок. В пустых состояниях
            // порядка нет, а «Фильтр» остаётся (кроме «Операций пока нет»).
            _allCategories = all;
            _monthTransactions = data.transactions;
            Widget withBar(
              Widget content, {
              required bool showSort,
              List<Transaction>? total,
            }) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ListBar(
                  filterSpoken: historyFilterSpoken(
                    widget.filter,
                    all,
                    accountName: _filterAccountName,
                  ),
                  filterActive: widget.filter.isActive,
                  onFilterPressed: widget.onFilterChanged == null
                      ? null
                      : _openFilter,
                  showSort: showSort,
                  sort: widget.sort,
                  onSortChanged: widget.onSortChanged,
                ),
                if (widget.filter.isActive)
                  _FilterStrip(
                    label: historyFilterLabel(
                      widget.filter,
                      all,
                      accountName: _filterAccountName,
                    ),
                    onReset: widget.onResetFilter,
                  ),
                if ((widget.filter.isActive || _searching) && total != null)
                  _FilteredTotal(shown: total),
                Expanded(child: content),
              ],
            );
            final nothingFound = _SearchNothingFound(
              query: widget.searchQuery.trim(),
              onClear: _clearSearch,
              onResetFilter: widget.filter.isActive
                  ? widget.onResetFilter
                  : null,
            );
            if (data.transactions.isEmpty) {
              final hasAny = widget.hasAnyTransactions;
              if (hasAny == null) return const _HistorySkeleton();
              // Пустой месяц, пришедший до ответа «всех месяцев», при поиске
              // не должен говорить «За … операций нет».
              if (hasAny && _searching) {
                return withBar(nothingFound, showSort: false);
              }
              final empty = _EmptyState(
                hasAnyTransactions: hasAny,
                month: data.month,
                hasOtherCurrencies: widget.hasOtherCurrencies,
                currencySymbol: widget.currencySymbol,
              );
              return hasAny ? withBar(empty, showSort: false) : empty;
            }
            // Запрос, фильтр и порядок применяем к пришедшему списку: поток от
            // них не пересоздаётся.
            final found = data.transactions.where(
              (t) => matchesHistorySearch(
                widget.searchQuery,
                comment: t.note,
                subcategoryName: byId[t.subcategoryId]?.name,
              ),
            );
            final shown = applyHistoryView(found, widget.filter, widget.sort);
            if (shown.isEmpty) {
              return withBar(
                _searching
                    ? nothingFound
                    : _NothingFound(
                        month: data.month,
                        onReset: widget.onResetFilter,
                      ),
                showSort: false,
              );
            }
            return withBar(
              _HistoryList(
                transactions: shown,
                categoriesById: byId,
                today: widget.today,
                byAmount: _byAmount(widget.sort),
                onTransactionTap: widget.onTransactionTap,
              ),
              showSort: true,
              total: shown,
            );
          },
        );
        return list;
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.onSearchChanged != null)
          _SearchField(controller: _search, onChanged: widget.onSearchChanged!),
        // Переключатель вне списка: при прокрутке остаётся на месте. Во время
        // поиска стрелок нет (ищем во всех месяцах); высота та же, что со
        // стрелками, чтобы список не прыгал.
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: PeriodSwitcher(
            label: _searching
                ? 'Во всех месяцах'
                : formatMonthTitle(widget.month),
            onPrevious: _searching ? null : widget.onPreviousMonth,
            onNext: _searching ? null : widget.onNextMonth,
            previousTooltip: 'Предыдущий месяц',
            nextTooltip: 'Следующий месяц',
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}

bool _byAmount(HistorySort sort) =>
    sort == HistorySort.largestFirst || sort == HistorySort.smallestFirst;

/// День в строке при сортировке по сумме: «Сегодня», «Вчера», «30 сентября»
/// (с годом, если год не текущий).
String _shortDayLabel(DateOnly day, DateOnly today) {
  if (day == today || day == today.addDays(-1)) {
    return dayLabel(day, today: today);
  }
  return day.year == today.year ? formatDayMonth(day) : formatDate(day);
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({
    required this.transactions,
    required this.categoriesById,
    required this.today,
    required this.byAmount,
    required this.onTransactionTap,
  });

  final List<Transaction> transactions;
  final Map<String, Category> categoriesById;
  final DateOnly today;

  /// Сортировка по сумме: без заголовков дней, день — во второй строке.
  final bool byAmount;
  final ValueChanged<Transaction> onTransactionTap;

  @override
  Widget build(BuildContext context) {
    // Плоский список: заголовок дня (DateOnly) и строки операций (Transaction).
    // Заголовки идут в порядке списка (при «Сначала старые» — по возрастанию).
    final items = <Object>[];
    DateOnly? currentDay;
    for (final t in transactions) {
      if (!byAmount && t.occurredOn != currentDay) {
        currentDay = t.occurredOn;
        items.add(t.occurredOn);
      }
      items.add(t);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 16),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item is DateOnly) {
          return _DayHeader(label: historyDayLabel(item, today: today));
        }
        final t = item as Transaction;
        final category = categoriesById[t.categoryId];
        final subcategory = t.subcategoryId == null
            ? null
            : categoriesById[t.subcategoryId];
        return _TransactionTile(
          transaction: t,
          title: _title(category, subcategory),
          iconKey: category?.iconKey,
          dayText: byAmount
              ? _shortDayLabel(t.occurredOn, today)
              : historyDayLabel(t.occurredOn, today: today),
          showDay: byAmount,
          onTap: () => onTransactionTap(t),
        );
      },
    );
  }

  /// «Категория» или «Категория · Подкатегория»; без категории — запасной текст.
  static String _title(Category? category, Category? subcategory) {
    if (category == null) return noCategoryLabel;
    if (subcategory == null) return category.name;
    return '${category.name} · ${subcategory.name}';
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          label,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _TransactionTile extends StatelessWidget {
  const _TransactionTile({
    required this.transaction,
    required this.title,
    required this.iconKey,
    required this.dayText,
    required this.showDay,
    required this.onTap,
  });

  final Transaction transaction;
  final String title;

  /// Показать день во второй строке («30 сентября · комментарий»).
  final bool showDay;

  /// Ключ иконки категории; `null` — категории нет, берётся запасная иконка.
  final String? iconKey;
  final String dayText;
  final VoidCallback onTap;

  static String _spoken(Money money) => spokenMoney(money);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isIncome = transaction.type == TransactionType.income;
    final accent = isIncome
        ? context.appColors.income
        : context.appColors.expense;
    final amountText =
        '${isIncome ? '+' : _minusSign}${formatMoney(transaction.amount)}';
    final note = transaction.note;

    // Сводная подпись для скринридера: тип, сумма словами, категория, день и
    // комментарий одной фразой; содержимое строки из озвучки исключено.
    final label = StringBuffer(isIncome ? 'Доход ' : 'Расход ')
      ..write(_spoken(transaction.amount))
      ..write(', $title, $dayText');
    if (note != null) label.write(', комментарий: $note');

    return Semantics(
      button: true,
      label: label.toString(),
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          // Зона нажатия не ниже 48 dp; при крупном шрифте строка растёт сама.
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: CategoryIconView(iconKey, size: 24),
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
                      if (note != null || showDay)
                        Text(
                          showDay
                              ? (note == null ? dayText : '$dayText · $note')
                              : note!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Сумма не занимает больше 45% ширины: очень длинная сумма при
                // крупном шрифте уменьшается, а не выталкивает название.
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
        ),
      ),
    );
  }
}

/// Пустое состояние: спросили базу, и операций нет. Либо их нет вообще, либо
/// пуст только выбранный [month].
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.hasAnyTransactions,
    required this.month,
    required this.hasOtherCurrencies,
    required this.currencySymbol,
  });

  final bool hasAnyTransactions;
  final DateOnly month;
  final Stream<bool>? hasOtherCurrencies;
  final String currencySymbol;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = hasAnyTransactions
        ? 'За ${formatMonthName(month)} ${month.year} операций нет'
        : 'Операций пока нет';
    final hint = hasAnyTransactions
        ? 'Выберите другой месяц стрелками вверху'
        : 'Добавьте расход или доход на вкладке «Главная»';
    // Прокрутка на случай крупного шрифта на маленьком экране.
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            OtherCurrenciesHint(
              hasOther: hasOtherCurrencies,
              symbol: currencySymbol,
            ),
          ],
        ),
      ),
    );
  }
}

/// Полоска «Фильтр: Расходы · Продукты» с кнопкой «Сбросить». Подпись
/// переносится на несколько строк, кнопка остаётся не ниже 48 dp.
class _FilterStrip extends StatelessWidget {
  const _FilterStrip({required this.label, required this.onReset});

  final String label;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 8),
      // Wrap, а не Row: при крупном шрифте кнопка уходит под подпись, а не
      // сжимает её до слова по буквам.
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Semantics(
            label: 'Сбросить фильтр',
            button: true,
            excludeSemantics: true,
            onTap: onReset,
            child: TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: onReset,
              child: const Text('Сбросить'),
            ),
          ),
        ],
      ),
    );
  }
}

const _sortLabels = {
  HistorySort.newestFirst: 'Сначала новые',
  HistorySort.oldestFirst: 'Сначала старые',
  HistorySort.largestFirst: 'Сначала крупные',
  HistorySort.smallestFirst: 'Сначала мелкие',
};

/// Строка над списком: слева кнопка «Фильтр» (с точкой, если фильтр включён),
/// справа кнопка текущего порядка с меню из четырёх вариантов (если [showSort]).
class _ListBar extends StatelessWidget {
  const _ListBar({
    required this.filterSpoken,
    required this.filterActive,
    required this.onFilterPressed,
    required this.showSort,
    required this.sort,
    required this.onSortChanged,
  });

  final String filterSpoken;
  final bool filterActive;
  final VoidCallback? onFilterPressed;
  final bool showSort;
  final HistorySort sort;
  final ValueChanged<HistorySort>? onSortChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      // Wrap: при крупном шрифте кнопки переносятся, а не переполняют строку.
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Semantics(
            label: filterSpoken,
            button: true,
            excludeSemantics: true,
            onTap: onFilterPressed,
            child: TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: onFilterPressed,
              icon: Badge(
                isLabelVisible: filterActive,
                smallSize: 8,
                child: const Icon(Icons.filter_list, size: 20),
              ),
              label: const Text('Фильтр'),
            ),
          ),
          if (showSort) _SortButton(sort: sort, onChanged: onSortChanged),
        ],
      ),
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.sort, required this.onChanged});

  final HistorySort sort;
  final ValueChanged<HistorySort>? onChanged;

  @override
  Widget build(BuildContext context) {
    final current = _sortLabels[sort]!;
    return MenuAnchor(
      menuChildren: [
        for (final option in HistorySort.values)
          MergeSemantics(
            child: Semantics(
              selected: option == sort,
              child: MenuItemButton(
                style: MenuItemButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
                trailingIcon: option == sort
                    ? const Icon(Icons.check, size: 20)
                    : null,
                onPressed: onChanged == null ? null : () => onChanged!(option),
                child: Text(_sortLabels[option]!),
              ),
            ),
          ),
      ],
      builder: (context, controller, _) => Semantics(
        label: 'Сортировка: ${current.toLowerCase()}',
        button: true,
        excludeSemantics: true,
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: TextButton.icon(
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          onPressed: () =>
              controller.isOpen ? controller.close() : controller.open(),
          icon: const Icon(Icons.swap_vert, size: 20),
          label: Text(current),
        ),
      ),
    );
  }
}

/// Поле поиска над списком: лупа, серая подсказка, крестик «Очистить поиск»,
/// пока в поле что-то есть.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) => TextField(
          controller: controller,
          onChanged: onChanged,
          maxLines: 1,
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Комментарий или подкатегория',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: value.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Очистить поиск',
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ),
    );
  }
}

/// Поиск ничего не нашёл (во всех месяцах, с учётом фильтра).
class _SearchNothingFound extends StatelessWidget {
  const _SearchNothingFound({
    required this.query,
    required this.onClear,
    required this.onResetFilter,
  });

  /// Запрос без пробелов по краям, как его показать в тексте.
  final String query;
  final VoidCallback onClear;

  /// «Сбросить фильтр»; `null` — фильтр выключен, кнопки нет.
  final VoidCallback? onResetFilter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ничего не найдено',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Нет операций с «$query» в комментарии или подкатегории',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: onClear,
              child: const Text('Очистить поиск'),
            ),
            if (onResetFilter != null) ...[
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: onResetFilter,
                child: const Text('Сбросить фильтр'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// В месяце операции есть, но под фильтр не подходит ни одна.
class _NothingFound extends StatelessWidget {
  const _NothingFound({required this.month, required this.onReset});

  final DateOnly month;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Ничего не найдено',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'За ${formatMonthName(month)} ${month.year} нет операций, '
              'подходящих под фильтр',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: onReset,
              child: const Text('Сбросить фильтр'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Серые строки-заглушки на месте будущего списка (без анимации: никаких
/// таймеров). Для скринридера — одна подпись «Загрузка».
class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.surfaceContainerHighest;

    Widget bar(double width, double height) => Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
    );

    Widget row() => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [bar(120, 14), const SizedBox(height: 6), bar(80, 10)],
            ),
          ),
          const SizedBox(width: 12),
          bar(64, 14),
        ],
      ),
    );

    // ListView без прокрутки: лишние строки просто обрезаются по краю экрана,
    // переполнения не бывает.
    return Semantics(
      label: 'Загрузка операций',
      child: ExcludeSemantics(
        child: ListView(
          key: historySkeletonKey,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 16),
          children: [for (var i = 0; i < 8; i++) row()],
        ),
      ),
    );
  }
}

/// Строка итога под полоской фильтра или при поиске: «7 операций, сумма
/// расходов» либо «12 операций, расходы и доходы» для смешанных типов. Суммы
/// цветом расхода и дохода. Период — от первого до последнего дня [shown]
/// (при поиске это несколько месяцев).
class _FilteredTotal extends StatelessWidget {
  const _FilteredTotal({required this.shown});

  final List<Transaction> shown;

  static DateRange _span(List<Transaction> transactions) {
    var first = transactions.first.occurredOn;
    var last = first;
    for (final t in transactions) {
      if (t.occurredOn < first) first = t.occurredOn;
      if (t.occurredOn > last) last = t.occurredOn;
    }
    return DateRange(first, last);
  }

  static String _spoken(Money money) => spokenMoney(money);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.appColors;
    final summary = summarizePeriod(
      shown,
      _span(shown),
      currency: shown.first.amount.currency,
    );
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final count = summary.count;
    final word = pluralRu(count, 'операция', 'операции', 'операций');
    final mixed = summary.expenseCount > 0 && summary.incomeCount > 0;
    final onlyIncome = summary.expenseCount == 0;

    final expense = '$_minusSign${formatMoney(summary.expense)}';
    final income = '+${formatMoney(summary.income)}';
    final spans = <InlineSpan>[TextSpan(text: '$count $word')];
    final spoken = StringBuffer('$count $word');
    void add(String prefix, String text, Color color) {
      spans
        ..add(TextSpan(text: ' \u00b7 $prefix'))
        ..add(
          TextSpan(
            text: text,
            style: TextStyle(color: color),
          ),
        );
    }

    if (mixed) {
      add('расходы ', expense, colors.expense);
      add('доходы ', income, colors.income);
      spoken
        ..write(', расходы минус ${_spoken(summary.expense)}')
        ..write(', доходы плюс ${_spoken(summary.income)}');
    } else if (onlyIncome) {
      add('', income, colors.income);
      spoken.write(', плюс ${_spoken(summary.income)}');
    } else {
      add('', expense, colors.expense);
      spoken.write(', минус ${_spoken(summary.expense)}');
    }

    return Semantics(
      label: spoken.toString(),
      liveRegion: true,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text.rich(TextSpan(style: style, children: spans)),
      ),
    );
  }
}
