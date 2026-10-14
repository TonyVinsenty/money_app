import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:money_app/core/ui/font_scale.dart';
import 'package:money_app/features/accounts/domain/account.dart';
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
  List<Account> accounts = const [],
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
      accounts: accounts,
    ),
  );
}

/// Подзаголовок раздела листа: titleSmall, жирность 600, цвет акцента.
TextStyle? _sectionStyle(BuildContext context) {
  final theme = Theme.of(context);
  return theme.textTheme.titleSmall?.copyWith(
    fontWeight: FontWeight.w600,
    color: theme.colorScheme.primary,
  );
}

/// Раздел «Счёт»: один выбор из «Все счета», счетов (уже отобранных по
/// основной валюте, архивные с пометкой) и «Без счёта».
class _AccountSection extends StatelessWidget {
  const _AccountSection({
    required this.accounts,
    required this.current,
    required this.onChanged,
  });

  final List<Account> accounts;
  final HistoryFilter current;
  final ValueChanged<HistoryFilter> onChanged;

  /// Порядок: живые по `sortOrder`, затем архивные (при равенстве имя, id).
  static List<Account> ordered(Iterable<Account> accounts) {
    final list = [...accounts];
    list.sort((a, b) {
      if (a.isArchived != b.isArchived) return a.isArchived ? 1 : -1;
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      if (byOrder != 0) return byOrder;
      final byName = a.name.compareTo(b.name);
      return byName != 0 ? byName : a.id.compareTo(b.id);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    HistoryFilter pick(HistoryAccountFilter account) => HistoryFilter(
      type: current.type,
      expenseCategoryIds: current.expenseCategoryIds,
      incomeCategoryIds: current.incomeCategoryIds,
      accountFilter: account,
    );
    final selectedAccount = current.accountFilter;
    // Один выбор из группы: читалка говорит «выбрано / не выбрано».
    Widget option(String label, bool selected, HistoryFilter next) => Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: label,
      onTap: () => onChanged(next),
      excludeSemantics: true,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        minVerticalPadding: 12,
        title: Text(label),
        selected: selected,
        trailing: selected ? const Icon(Icons.check) : null,
        onTap: () => onChanged(next),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Semantics(
          header: true,
          child: Text('Счёт', style: _sectionStyle(context)),
        ),
        option(
          'Все счета',
          selectedAccount is AnyAccount,
          pick(const AnyAccount()),
        ),
        for (final a in ordered(accounts))
          option(
            a.isArchived ? '${a.name} (в архиве)' : a.name,
            selectedAccount == OneAccount(a.id),
            pick(OneAccount(a.id)),
          ),
        option(
          'Без счёта',
          selectedAccount is NoAccount,
          pick(const NoAccount()),
        ),
      ],
    );
  }
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
      // Если набор был `null` («все»), он собирается только из видимых
      // категорий показанного месяца: операции «Без категории» и архивных
      // категорий других месяцев после снятия галочки из фильтра выпадают.
      final next = {...(selected ?? visibleIds)};
      checked ? next.add(id) : next.remove(id);
      // Все отмечены — ограничения по категориям нет.
      onSelected(next.containsAll(visibleIds) ? null : next);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        // Заголовок и кнопки в одной строке. При крупном шрифте (больше 130 %)
        // кнопки уходят на вторую строку, а не вылезают за край.
        Builder(
          builder: (context) {
            final header = Semantics(
              header: true,
              child: Text(title, style: _sectionStyle(context)),
            );
            final buttons = [
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
            ];
            // Узкий экран (360 dp) тоже переносит кнопки: в строку не влезают.
            final large =
                fontScaleFrom(MediaQuery.textScalerOf(context)) > 1.3 ||
                MediaQuery.sizeOf(context).width < 400;
            if (large) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  header,
                  Wrap(alignment: WrapAlignment.end, children: buttons),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: header),
                ...buttons,
              ],
            );
          },
        ),
        if (selected != null && selected!.isEmpty)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Не выбрана ни одна категория',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        for (final c in visible)
          if (theme.platform == TargetPlatform.iOS)
            // iPhone: галочка справа, как в разделе «Счёт». Читалка слышит
            // «выбрано» так же, как у чекбокса.
            Builder(
              builder: (context) {
                final checked = selected == null || selected!.contains(c.id);
                return Semantics(
                  checked: checked,
                  button: true,
                  label: c.name,
                  onTap: () => toggle(c.id, !checked),
                  excludeSemantics: true,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    minVerticalPadding: 12,
                    title: Text(c.name),
                    selected: checked,
                    trailing: checked ? const Icon(Icons.check) : null,
                    onTap: () => toggle(c.id, !checked),
                  ),
                );
              },
            )
          else
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

/// Шапка листа: «Сбросить» слева, «Фильтр» по центру, «Готово» справа. Если
/// по ширине не помещается (крупный шрифт, узкий экран), «Фильтр» уходит
/// отдельной строкой под ряд кнопок; текст не сжимается.
class _SheetHeader extends StatelessWidget {
  const _SheetHeader({required this.onReset, required this.onDone});

  final VoidCallback? onReset;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final titleStyle = theme.textTheme.titleLarge;
    final buttonStyle = theme.textTheme.labelLarge;
    double textWidth(String text, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout();
      return painter.width;
    }

    // Кнопка: текст + поля (по 12 dp с каждой стороны) + запас.
    final side =
        [
          textWidth('Сбросить', buttonStyle),
          textWidth('Готово', buttonStyle),
        ].reduce((a, b) => a > b ? a : b) +
        32;
    final title = Semantics(
      header: true,
      child: Text('Фильтр', style: titleStyle, textAlign: TextAlign.center),
    );
    final reset = TextButton(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      onPressed: onReset,
      child: const Text('Сбросить'),
    );
    final done = TextButton(
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      onPressed: onDone,
      child: const Text('Готово'),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fits =
              2 * side + textWidth('Фильтр', titleStyle) + 16 <=
              constraints.maxWidth;
          if (fits) {
            return SizedBox(
              height: 56,
              child: NavigationToolbar(
                centerMiddle: true,
                leading: reset,
                middle: title,
                trailing: done,
              ),
            );
          }
          // Две кнопки в ряд, а если и они не помещаются — друг под другом.
          final twoInRow =
              textWidth('Сбросить', buttonStyle) +
                  textWidth('Готово', buttonStyle) +
                  64 <=
              constraints.maxWidth;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (twoInRow)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [reset, done],
                )
              else ...[
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: reset,
                ),
                Align(alignment: AlignmentDirectional.centerEnd, child: done),
              ],
              Padding(padding: const EdgeInsets.only(bottom: 8), child: title),
            ],
          );
        },
      ),
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
    this.accounts = const [],
    super.key,
  });

  /// Счета основной валюты (живые и архивные); пусто - раздела «Счёт» нет.
  final List<Account> accounts;

  final ValueListenable<HistoryFilter> filter;
  final ValueChanged<HistoryFilter> onChanged;
  final List<Category> categories;
  final List<Transaction> monthTransactions;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<HistoryFilter>(
      valueListenable: filter,
      builder: (context, current, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Шапка закреплена: «Сбросить» слева, «Фильтр» по центру, «Готово»
          // справа; не уезжает вместе с прокруткой.
          _SheetHeader(
            onReset: current.isActive
                ? () => onChanged(HistoryFilter.off)
                : null,
            onDone: () => Navigator.of(context).pop(),
          ),
          // Прокрутка: при крупном шрифте содержимое не помещается в лист.
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<HistoryTypeFilter>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: HistoryTypeFilter.all,
                        label: Text('Все'),
                      ),
                      ButtonSegment(
                        value: HistoryTypeFilter.expense,
                        label: Text('Расходы'),
                      ),
                      ButtonSegment(
                        value: HistoryTypeFilter.income,
                        label: Text('Доходы'),
                      ),
                    ],
                    selected: {current.type},
                    // Наборы категорий сохраняются: меняется только тип.
                    onSelectionChanged: (selection) => onChanged(
                      HistoryFilter(
                        type: selection.first,
                        expenseCategoryIds: current.expenseCategoryIds,
                        incomeCategoryIds: current.incomeCategoryIds,
                        accountFilter: current.accountFilter,
                      ),
                    ),
                  ),
                  if (accounts.isNotEmpty)
                    _AccountSection(
                      accounts: accounts,
                      current: current,
                      onChanged: onChanged,
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
                          accountFilter: current.accountFilter,
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
                          accountFilter: current.accountFilter,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
