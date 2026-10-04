import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:money_app/core/ui/category_icons.dart';
import 'package:money_app/features/categories/domain/category.dart';

/// Кнопки у строки категории (и подкатегории).
const categoriesArchiveAction = 'В архив';
const categoriesRestoreAction = 'Вернуть из архива';
const categoriesSubcategoriesAction = 'Подкатегории';

/// Кнопка отмены в сообщении об архиве.
const categoriesUndoAction = 'Вернуть';

/// Сколько сообщение об архиве висит на экране: столько же, сколько сообщение
/// об операции с «Отменить» (`SavedSnackBar.duration`). Само значение сюда
/// скопировано: фича не импортирует чужой `presentation` (ADR 0002).
const categoriesArchivedDuration = Duration(seconds: 6);

/// Подпись кнопки-карандаша у строки: имя нужно скринридеру и подсказке.
String categoriesRenameLabel(String name) => 'Переименовать: $name';

/// Подпись кнопки перехода к подкатегориям (и подсказка к ней).
String categoriesSubcategoriesLabel(String name) => 'Подкатегории: $name';

/// Строка под названием категории, у которой есть подкатегории.
String categoriesSubcategoryCount(int count) => 'Подкатегорий: $count';

/// Заголовок свёрнутого раздела архива: «Архив (3)».
String categoriesArchiveTitle(int count) => 'Архив ($count)';

/// Объявление скринридеру после перемещения: «Кафе: позиция 2 из 5».
String categoriesMovedAnnouncement(String name, int position, int total) =>
    '$name: позиция $position из $total';

/// Подпись кнопки для скринридера: к слову-действию добавляется имя, иначе
/// все кнопки в списке звучат одинаково.
String categoriesArchiveLabel(String name) => '$categoriesArchiveAction: $name';
String categoriesRestoreLabel(String name) => '$categoriesRestoreAction: $name';

/// Список живых категорий (их можно переставлять) и свёрнутый раздел архива
/// внизу. Им пользуются оба экрана: «Категории» (один вид) и «Подкатегории»
/// (одна родительская категория).
///
/// [categories] — всё, что отдал поток базы; какие из них показывать в этом
/// списке, решает [belongs]. Порядок — как отдал репозиторий (`sortOrder`).
///
/// Перестановка: пока идёт запись, показываем порядок, который человек только
/// что задал, иначе список на миг «отскочил» бы на старый, пока база не
/// ответила. Порядок из потока снова главный, когда пришёл новый список или
/// запись не удалась.
class CategoryList extends StatefulWidget {
  const CategoryList({
    required this.categories,
    required this.belongs,
    required this.archiveKey,
    required this.archiveNote,
    required this.emptyText,
    required this.onArchive,
    required this.onRestore,
    required this.onRename,
    required this.onReorder,
    this.subcategoryCounts,
    this.onOpenSubcategories,
    super.key,
  });

  final List<Category> categories;

  /// Какие из [categories] относятся к этому списку.
  final bool Function(Category category) belongs;

  /// Уникальное имя раздела архива (у соседних списков оно разное, чтобы
  /// состояние «свёрнут/развёрнут» не путалось).
  final String archiveKey;

  /// Пояснение первой строкой в развёрнутом архиве.
  final String archiveNote;

  /// Пока в списке нет ни одной живой строки.
  final String emptyText;

  final void Function(Category category) onArchive;
  final void Function(Category category) onRestore;
  final void Function(Category category) onRename;

  /// Записывает порядок живых строк; `true`, если запись удалась (при ошибке
  /// сообщение уже показано).
  final Future<bool> Function(List<String> orderedIds) onReorder;

  /// Сколько живых подкатегорий у категории (по id); нет записи — ноль. Если
  /// `null`, у строк нет ни кнопки, ни счётчика подкатегорий.
  final Map<String, int>? subcategoryCounts;

  /// Открывает экран подкатегорий; кнопка есть только у живых строк.
  final void Function(Category category)? onOpenSubcategories;

  @override
  State<CategoryList> createState() => _CategoryListState();
}

class _CategoryListState extends State<CategoryList> {
  /// Порядок id, заданный человеком и ещё не подтверждённый потоком.
  List<String>? _localOrder;

  /// Идёт запись порядка: новую перестановку в это время не принимаем.
  bool _saving = false;

  List<Category> _own() => [
    for (final c in widget.categories)
      if (widget.belongs(c)) c,
  ];

  List<Category> _streamLive() => [
    for (final c in _own())
      if (!c.isArchived) c,
  ];

  /// Живые строки в порядке, который видит человек.
  List<Category> _shownLive() {
    final live = _streamLive();
    final order = _localOrder;
    if (order == null) return live;
    final known = {for (var i = 0; i < order.length; i++) order[i]: i};
    return [
      ...[
        for (final c in live)
          if (known.containsKey(c.id)) c,
      ]..sort((a, b) => known[a.id]!.compareTo(known[b.id]!)),
      for (final c in live)
        if (!known.containsKey(c.id)) c,
    ];
  }

  @override
  void didUpdateWidget(CategoryList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Пришёл новый список из базы: он и есть правда.
    if (!_saving && !identical(oldWidget.categories, widget.categories)) {
      _localOrder = null;
    }
  }

  /// [target] уже итоговый индекс (`onReorderItem` сам учитывает сдвиг).
  Future<void> _handleReorder(int oldIndex, int target) async {
    if (_saving) return;
    if (target == oldIndex) return;
    final live = _shownLive();
    final moved = live.removeAt(oldIndex);
    live.insert(target, moved);
    final ids = [for (final c in live) c.id];
    setState(() {
      _localOrder = ids;
      _saving = true;
    });
    final ok = await widget.onReorder(ids);
    if (!mounted) return;
    final streamIds = [for (final c in _streamLive()) c.id];
    setState(() {
      _saving = false;
      // Ошибка или поток уже показывает то же самое: локальный порядок не нужен.
      if (!ok || _sameIds(streamIds, ids)) _localOrder = null;
    });
    if (ok) {
      unawaited(
        SemanticsService.sendAnnouncement(
          View.of(context),
          categoriesMovedAnnouncement(moved.name, target + 1, ids.length),
          Directionality.of(context),
        ),
      );
    }
  }

  static bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final live = _shownLive();
    final archived = [
      for (final c in _own())
        if (c.isArchived) c,
    ];
    final counts = widget.subcategoryCounts;
    final openSubcategories = widget.onOpenSubcategories;
    // Кнопок «Переместить вверх/вниз/в начало/в конец» для скринридера отдельно
    // делать не нужно: ReorderableListView сам вешает их на каждую строку (без
    // недоступных у крайних) и озвучивает по-русски.
    return ReorderableListView(
      // Свои ручки: по умолчанию на телефоне тянуть пришлось бы долгим
      // нажатием по всей строке, а ручки не было бы видно.
      buildDefaultDragHandles: false,
      // Снизу запас под кнопку «Добавить…»: она не закрывает последнюю строку.
      padding: const EdgeInsets.only(bottom: 96),
      onReorderItem: (oldIndex, newIndex) =>
          unawaited(_handleReorder(oldIndex, newIndex)),
      header: live.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(24),
              child: Text(widget.emptyText, textAlign: TextAlign.center),
            )
          : null,
      // Архив не переставляется и остаётся внизу.
      footer: archived.isEmpty
          ? null
          : ExpansionTile(
              key: ValueKey<String>(widget.archiveKey),
              title: Text(categoriesArchiveTitle(archived.length)),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      widget.archiveNote,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                for (final c in archived)
                  _CategoryRow(
                    key: ValueKey<String>(c.id),
                    category: c,
                    actionText: categoriesRestoreAction,
                    actionIcon: Icons.unarchive_outlined,
                    actionLabel: categoriesRestoreLabel(c.name),
                    onPressed: () => widget.onRestore(c),
                    onRename: () => widget.onRename(c),
                  ),
              ],
            ),
      children: [
        for (var i = 0; i < live.length; i++)
          _CategoryRow(
            key: ValueKey<String>(live[i].id),
            category: live[i],
            actionText: categoriesArchiveAction,
            actionIcon: Icons.archive_outlined,
            actionLabel: categoriesArchiveLabel(live[i].name),
            onPressed: () => widget.onArchive(live[i]),
            onRename: () => widget.onRename(live[i]),
            dragIndex: i,
            subcategoryCount: counts == null ? null : counts[live[i].id] ?? 0,
            onOpenSubcategories: openSubcategories == null
                ? null
                : () => openSubcategories(live[i]),
          ),
      ],
    );
  }
}

/// Строка категории: иконка, имя и под ним кнопка. Кнопка стоит под именем, а
/// не сбоку: при крупном шрифте длинное имя и длинная подпись не теснят друг
/// друга.
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.actionText,
    required this.actionIcon,
    required this.actionLabel,
    required this.onPressed,
    this.onRename,
    this.dragIndex,
    this.subcategoryCount,
    this.onOpenSubcategories,
    super.key,
  });

  final Category category;
  final String actionText;

  /// Иконка перед текстом действия («В архив», «Вернуть из архива»).
  final IconData actionIcon;
  final String actionLabel;
  final VoidCallback onPressed;

  /// Переименование (карандаш справа).
  final VoidCallback? onRename;

  /// Место строки в переставляемом списке; ручка перетаскивания есть только у
  /// живых строк (у архивных `null`).
  final int? dragIndex;

  /// Сколько подкатегорий у категории; `null` — счётчик не показываем.
  final int? subcategoryCount;

  /// Переход к подкатегориям; `null` — кнопки нет.
  final VoidCallback? onOpenSubcategories;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = subcategoryCount;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Первая строка: иконка, имя и справа карандаш с ручкой. Имя не делит
          // ширину с кнопками, поэтому длинное название читается целиком.
          Row(
            children: [
              Icon(categoryIconFor(category.iconKey)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  category.name,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // Карандаш справа: узкая кнопка не отнимает у имени места и при
              // крупном шрифте (её размер не растёт вместе с текстом).
              if (onRename != null)
                IconButton(
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: categoriesRenameLabel(category.name),
                  onPressed: onRename,
                ),
              // Ручка: тянуть можно только за неё, чтобы не мешать прокрутке.
              // Скринридеру ручка не нужна: у строки есть действия «Переместить».
              if (dragIndex != null)
                ExcludeSemantics(
                  child: ReorderableDragStartListener(
                    index: dragIndex!,
                    child: const SizedBox(
                      width: 48,
                      height: 48,
                      child: Icon(Icons.drag_handle),
                    ),
                  ),
                ),
            ],
          ),
          // Вторая часть: подпись и кнопки стоят под названием (отступ 40 dp =
          // ширина иконки и промежутка, чтобы выровняться по имени).
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (count != null && count > 0)
                  Text(
                    categoriesSubcategoryCount(count),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                // Wrap, а не Row: при крупном шрифте или длинном имени вторая
                // кнопка переносится на следующую строку, а не вылезает
                // за край экрана.
                Wrap(
                  spacing: 16,
                  runSpacing: 0,
                  children: [
                    _action(
                      context,
                      icon: actionIcon,
                      onPressed: onPressed,
                      // Скринридер читает действие вместе с именем категории.
                      label: Semantics(
                        label: actionLabel,
                        excludeSemantics: true,
                        child: Text(actionText),
                      ),
                    ),
                    if (onOpenSubcategories != null)
                      _action(
                        context,
                        icon: Icons.account_tree_outlined,
                        onPressed: onOpenSubcategories!,
                        label: Semantics(
                          label: categoriesSubcategoriesLabel(category.name),
                          excludeSemantics: true,
                          child: const Text(categoriesSubcategoriesAction),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // Разделитель между строками: отступ слева 40 dp плюс 16 dp полей
          // строки даёт линию от начала имени.
          Divider(
            height: 1,
            indent: 40,
            color: theme.colorScheme.outlineVariant,
          ),
        ],
      ),
    );
  }

  /// Кнопка действия в строке: иконка и текст цветом темы (`primary`), чтобы
  /// было видно, что на них можно нажать. Высота нажатия — не меньше 48 dp.
  Widget _action(
    BuildContext context, {
    required IconData icon,
    required VoidCallback onPressed,
    required Widget label,
  }) {
    return TextButton(
      style: TextButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.primary,
        minimumSize: const Size(48, 48),
        padding: EdgeInsets.zero,
        alignment: Alignment.centerLeft,
      ),
      onPressed: onPressed,
      // Обычный TextButton с Row внутри, а не TextButton.icon: тот создаёт
      // подкласс, и поиск `find.byType(TextButton)` в тестах перестаёт его видеть.
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Иконка декоративная: её смысл уже есть в тексте кнопки.
          ExcludeSemantics(child: Icon(icon, size: 18)),
          const SizedBox(width: 8),
          // Flexible: при крупном шрифте длинная подпись переносится внутри
          // кнопки, а не вылезает за её край.
          Flexible(child: label),
        ],
      ),
    );
  }
}
