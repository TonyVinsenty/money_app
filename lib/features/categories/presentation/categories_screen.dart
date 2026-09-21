import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:money_app/core/ui/async_view.dart';
import 'package:money_app/core/ui/category_icons.dart';
import 'package:money_app/core/ui/category_rule_text.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/categories/domain/category_rules.dart';

/// Заголовок экрана управления категориями.
const categoriesScreenTitle = 'Категории';

/// Названия двух видов (вкладки вверху экрана).
const categoriesExpenseTab = 'Расходы';
const categoriesIncomeTab = 'Доходы';

/// Кнопки у строки категории.
const categoriesArchiveAction = 'В архив';
const categoriesRestoreAction = 'Вернуть из архива';

/// Кнопка создания новой категории.
const categoriesAddAction = 'Добавить категорию';

/// Подпись кнопки-карандаша у строки: имя нужно скринридеру и подсказке.
String categoriesRenameLabel(String name) => 'Переименовать: $name';

/// Пока в виде нет ни одной живой категории.
const categoriesEmptyText = 'Категорий пока нет';

/// Ошибка чтения списка из базы.
const categoriesLoadErrorText = 'Не удалось загрузить категории';

/// Заголовок свёрнутого раздела архива: «Архив (3)».
String categoriesArchiveTitle(int count) => 'Архив ($count)';

/// Объявление скринридеру после перемещения: «Кафе: позиция 2 из 5».
String categoriesMovedAnnouncement(String name, int position, int total) =>
    '$name: позиция $position из $total';

/// Подпись кнопки для скринридера: к слову-действию добавляется имя, иначе
/// все кнопки в списке звучат одинаково.
String categoriesArchiveLabel(String name) => '$categoriesArchiveAction: $name';
String categoriesRestoreLabel(String name) => '$categoriesRestoreAction: $name';

/// Экран «Категории» (открывается из «Настроек» по именованному маршруту).
///
/// Два вида, «Расходы» и «Доходы»; в каждом живые категории верхнего уровня в
/// порядке репозитория (`sortOrder`) и свёрнутый раздел «Архив (N)». Архив
/// обратим, поэтому подтверждения нет. Подкатегории здесь пока не показываются.
///
/// Форма создания и переименования лежит на другом маршруте: её открывают
/// колбэки [onCreate] (с видом открытой вкладки) и [onRename], их даёт
/// приложение.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({
    required this.categories,
    required this.onCreate,
    required this.onRename,
    super.key,
  });

  final CategoriesRepository categories;
  final void Function(CategoryKind kind) onCreate;
  final void Function(Category category) onRename;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  /// Поток создаём один раз: в `build` каждая перерисовка подписывалась бы
  /// заново.
  late final Stream<List<Category>> _stream;

  /// Категории, по которым сейчас идёт запись: второй тап игнорируется.
  final _pending = <String>{};

  @override
  void initState() {
    super.initState();
    _stream = widget.categories.watchAll();
  }

  Future<void> _change(
    Category category,
    Future<void> Function(String id) action,
  ) async {
    if (!_pending.add(category.id)) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action(category.id);
    } on CategoryRuleException catch (error) {
      _showError(messenger, categoryRuleMessage(error.rule));
    } on Object {
      // Сбой базы и всё прочее: человек исправить не может.
      _showError(messenger, categorySaveFailedText);
    } finally {
      _pending.remove(category.id);
    }
  }

  /// Записывает новый порядок живых категорий вида. `false` при любой ошибке
  /// (сообщение показано).
  Future<bool> _reorder(List<String> orderedIds) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.categories.reorder(orderedIds);
      return true;
    } on Object {
      _showError(messenger, categorySaveFailedText);
      return false;
    }
  }

  void _showError(ScaffoldMessengerState messenger, String text) {
    if (!mounted) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(categoriesScreenTitle),
          bottom: const TabBar(
            tabs: [
              Tab(text: categoriesExpenseTab),
              Tab(text: categoriesIncomeTab),
            ],
          ),
        ),
        // Builder: вид открытой вкладки читаем из DefaultTabController, а он
        // виден только ниже по дереву.
        floatingActionButton: Builder(
          builder: (context) => FloatingActionButton.extended(
            onPressed: () {
              final index = DefaultTabController.of(context).index;
              widget.onCreate(
                index == 0 ? CategoryKind.expense : CategoryKind.income,
              );
            },
            icon: const Icon(Icons.add),
            label: const Text(categoriesAddAction),
          ),
        ),
        body: SafeArea(
          child: AsyncView<List<Category>>(
            stream: _stream,
            errorBuilder: (context, error) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  categoriesLoadErrorText,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            dataBuilder: (context, data) => TabBarView(
              children: [
                _KindList(
                  categories: data,
                  kind: CategoryKind.expense,
                  onArchive: (c) =>
                      unawaited(_change(c, widget.categories.archive)),
                  onRestore: (c) =>
                      unawaited(_change(c, widget.categories.restore)),
                  onRename: widget.onRename,
                  onReorder: _reorder,
                ),
                _KindList(
                  categories: data,
                  kind: CategoryKind.income,
                  onArchive: (c) =>
                      unawaited(_change(c, widget.categories.archive)),
                  onRestore: (c) =>
                      unawaited(_change(c, widget.categories.restore)),
                  onRename: widget.onRename,
                  onReorder: _reorder,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Список одного вида: живые категории (их можно переставлять) и раздел
/// архива внизу.
///
/// Перестановка: пока идёт запись, показываем порядок, который человек только
/// что задал ([_localOrder]), иначе список на миг «отскочил» бы на старый
/// порядок, пока база не ответила. Порядок из потока снова главный, когда
/// пришёл новый список или запись не удалась.
class _KindList extends StatefulWidget {
  const _KindList({
    required this.categories,
    required this.kind,
    required this.onArchive,
    required this.onRestore,
    required this.onRename,
    required this.onReorder,
  });

  final List<Category> categories;
  final CategoryKind kind;
  final void Function(Category category) onArchive;
  final void Function(Category category) onRestore;
  final void Function(Category category) onRename;

  /// Записывает порядок живых категорий; `true`, если запись удалась (при
  /// ошибке сообщение уже показано).
  final Future<bool> Function(List<String> orderedIds) onReorder;

  @override
  State<_KindList> createState() => _KindListState();
}

class _KindListState extends State<_KindList> {
  /// Порядок id, заданный человеком и ещё не подтверждённый потоком.
  List<String>? _localOrder;

  /// Идёт запись порядка: новую перестановку в это время не принимаем.
  bool _saving = false;

  /// watchAll отдаёт и подкатегории, и архивные: оставляем верхний уровень
  /// своего вида. Порядок — как отдал репозиторий (`sortOrder`).
  List<Category> _own() => [
    for (final c in widget.categories)
      if (c.isTopLevel && c.kind == widget.kind) c,
  ];

  List<Category> _streamLive() => [
    for (final c in _own())
      if (!c.isArchived) c,
  ];

  /// Живые категории в порядке, который видит человек.
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
  void didUpdateWidget(_KindList oldWidget) {
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
    // Кнопок «Переместить вверх/вниз/в начало/в конец» для скринридера отдельно
    // делать не нужно: ReorderableListView сам вешает их на каждую строку (без
    // недоступных у крайних) и озвучивает по-русски.
    return ReorderableListView(
      // Свои ручки: по умолчанию на телефоне тянуть пришлось бы долгим
      // нажатием по всей строке, а ручки не было бы видно.
      buildDefaultDragHandles: false,
      // Снизу запас под кнопку «Добавить категорию»: она не закрывает
      // последнюю строку.
      padding: const EdgeInsets.only(bottom: 96),
      onReorderItem: (oldIndex, newIndex) =>
          unawaited(_handleReorder(oldIndex, newIndex)),
      header: live.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text(categoriesEmptyText, textAlign: TextAlign.center),
            )
          : null,
      // Архив не переставляется и остаётся внизу.
      footer: archived.isEmpty
          ? null
          : ExpansionTile(
              key: ValueKey<String>('archive-${widget.kind.name}'),
              title: Text(categoriesArchiveTitle(archived.length)),
              children: [
                for (final c in archived)
                  _CategoryRow(
                    key: ValueKey<String>(c.id),
                    category: c,
                    actionText: categoriesRestoreAction,
                    actionLabel: categoriesRestoreLabel(c.name),
                    onPressed: () => widget.onRestore(c),
                  ),
              ],
            ),
      children: [
        for (var i = 0; i < live.length; i++)
          _CategoryRow(
            key: ValueKey<String>(live[i].id),
            category: live[i],
            actionText: categoriesArchiveAction,
            actionLabel: categoriesArchiveLabel(live[i].name),
            onPressed: () => widget.onArchive(live[i]),
            onRename: () => widget.onRename(live[i]),
            dragIndex: i,
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
    required this.actionLabel,
    required this.onPressed,
    this.onRename,
    this.dragIndex,
    super.key,
  });

  final Category category;
  final String actionText;
  final String actionLabel;
  final VoidCallback onPressed;

  /// Переименование; только у живых категорий (у архивных `null`).
  final VoidCallback? onRename;

  /// Место строки в переставляемом списке; ручка перетаскивания есть только у
  /// живых категорий (у архивных `null`).
  final int? dragIndex;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(categoryIconFor(category.iconKey)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.name,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                    padding: EdgeInsets.zero,
                    alignment: Alignment.centerLeft,
                  ),
                  onPressed: onPressed,
                  // Скринридер читает действие вместе с именем категории.
                  child: Semantics(
                    label: actionLabel,
                    excludeSemantics: true,
                    child: Text(actionText),
                  ),
                ),
              ],
            ),
          ),
          // Карандаш справа: узкая кнопка не отнимает у имени места и при
          // крупном шрифте (её размер не растёт вместе с текстом).
          if (onRename != null)
            IconButton(
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
    );
  }
}
