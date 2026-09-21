import 'dart:async';

import 'package:flutter/material.dart';
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
                ),
                _KindList(
                  categories: data,
                  kind: CategoryKind.income,
                  onArchive: (c) =>
                      unawaited(_change(c, widget.categories.archive)),
                  onRestore: (c) =>
                      unawaited(_change(c, widget.categories.restore)),
                  onRename: widget.onRename,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Список одного вида: живые категории и раздел архива.
class _KindList extends StatelessWidget {
  const _KindList({
    required this.categories,
    required this.kind,
    required this.onArchive,
    required this.onRestore,
    required this.onRename,
  });

  final List<Category> categories;
  final CategoryKind kind;
  final void Function(Category category) onArchive;
  final void Function(Category category) onRestore;
  final void Function(Category category) onRename;

  @override
  Widget build(BuildContext context) {
    // watchAll отдаёт и подкатегории, и архивные: оставляем верхний уровень
    // своего вида. Порядок — как отдал репозиторий (`sortOrder`).
    final own = [
      for (final c in categories)
        if (c.isTopLevel && c.kind == kind) c,
    ];
    final live = [
      for (final c in own)
        if (!c.isArchived) c,
    ];
    final archived = [
      for (final c in own)
        if (c.isArchived) c,
    ];
    return ListView(
      // Снизу запас под кнопку «Добавить категорию»: она не закрывает
      // последнюю строку.
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        if (live.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(categoriesEmptyText, textAlign: TextAlign.center),
          ),
        for (final c in live)
          _CategoryRow(
            key: ValueKey<String>(c.id),
            category: c,
            actionText: categoriesArchiveAction,
            actionLabel: categoriesArchiveLabel(c.name),
            onPressed: () => onArchive(c),
            onRename: () => onRename(c),
          ),
        if (archived.isNotEmpty)
          ExpansionTile(
            key: ValueKey<String>('archive-${kind.name}'),
            title: Text(categoriesArchiveTitle(archived.length)),
            children: [
              for (final c in archived)
                _CategoryRow(
                  key: ValueKey<String>(c.id),
                  category: c,
                  actionText: categoriesRestoreAction,
                  actionLabel: categoriesRestoreLabel(c.name),
                  onPressed: () => onRestore(c),
                ),
            ],
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
    super.key,
  });

  final Category category;
  final String actionText;
  final String actionLabel;
  final VoidCallback onPressed;

  /// Переименование; только у живых категорий (у архивных `null`).
  final VoidCallback? onRename;

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
        ],
      ),
    );
  }
}
