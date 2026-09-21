import 'dart:async';

import 'package:flutter/material.dart';
import 'package:money_app/core/ui/async_view.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/categories/presentation/category_actions.dart';
import 'package:money_app/features/categories/presentation/category_list.dart';

// Тексты, общие с экраном подкатегорий, лежат рядом со списком.
export 'package:money_app/features/categories/presentation/category_list.dart'
    show
        categoriesArchiveAction,
        categoriesArchiveLabel,
        categoriesArchiveTitle,
        categoriesArchivedDuration,
        categoriesMovedAnnouncement,
        categoriesRenameLabel,
        categoriesRestoreAction,
        categoriesRestoreLabel,
        categoriesSubcategoriesLabel,
        categoriesSubcategoryCount,
        categoriesUndoAction;

/// Заголовок экрана управления категориями.
const categoriesScreenTitle = 'Категории';

/// Названия двух видов (вкладки вверху экрана).
const categoriesExpenseTab = 'Расходы';
const categoriesIncomeTab = 'Доходы';

/// Кнопка создания новой категории.
const categoriesAddAction = 'Добавить категорию';

/// Сообщение после отправки в архив.
String categoriesArchivedMessage(String name) => 'Категория «$name» в архиве';

/// Пояснение первой строкой в развёрнутом архиве.
const categoriesArchiveNote = 'Старые операции по этим категориям сохранены';

/// Пока в виде нет ни одной живой категории.
const categoriesEmptyText = 'Категорий пока нет';

/// Ошибка чтения списка из базы.
const categoriesLoadErrorText = 'Не удалось загрузить категории';

/// Экран «Категории» (открывается из «Настроек» по именованному маршруту).
///
/// Два вида, «Расходы» и «Доходы»; в каждом живые категории верхнего уровня в
/// порядке репозитория (`sortOrder`) и свёрнутый раздел «Архив (N)». Архив
/// обратим, поэтому подтверждения нет. У живой категории есть кнопка перехода
/// к её подкатегориям; сами подкатегории на этом экране не показываются.
///
/// Форма создания и переименования и экран подкатегорий лежат на других
/// маршрутах: их открывают колбэки [onCreate] (с видом открытой вкладки),
/// [onRename] и [onOpenSubcategories], их даёт приложение. Колбэк возвращает
/// Future, который завершается, когда экран закрыли: пока он открыт, повторный
/// тап (двойной) второго экрана не открывает.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({
    required this.categories,
    required this.onCreate,
    required this.onRename,
    required this.onOpenSubcategories,
    super.key,
  });

  final CategoriesRepository categories;
  final Future<void> Function(CategoryKind kind) onCreate;
  final Future<void> Function(Category category) onRename;
  final Future<void> Function(Category category) onOpenSubcategories;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen>
    with CategoryActions<CategoriesScreen> {
  /// Поток создаём один раз: в `build` каждая перерисовка подписывалась бы
  /// заново.
  late final Stream<List<Category>> _stream;

  @override
  CategoriesRepository get categoriesRepository => widget.categories;

  @override
  String archivedMessage(String name) => categoriesArchivedMessage(name);

  @override
  void initState() {
    super.initState();
    _stream = widget.categories.watchAll();
  }

  /// Сколько живых подкатегорий у каждой категории (по id родителя).
  Map<String, int> _subcategoryCounts(List<Category> all) {
    final counts = <String, int>{};
    for (final c in all) {
      final parentId = c.parentId;
      if (parentId != null && !c.isArchived) {
        counts[parentId] = (counts[parentId] ?? 0) + 1;
      }
    }
    return counts;
  }

  /// watchAll отдаёт и подкатегории, и архивные: в списке вида оставляем
  /// верхний уровень своего вида.
  Widget _kindList(List<Category> data, CategoryKind kind) {
    return CategoryList(
      categories: data,
      belongs: (c) => c.isTopLevel && c.kind == kind,
      archiveKey: 'archive-${kind.name}',
      archiveNote: categoriesArchiveNote,
      emptyText: categoriesEmptyText,
      subcategoryCounts: _subcategoryCounts(data),
      onOpenSubcategories: (c) =>
          unawaited(openOnce(() => widget.onOpenSubcategories(c))),
      onArchive: (c) => unawaited(archiveCategory(c)),
      onRestore: (c) => unawaited(restoreCategory(c)),
      onRename: (c) => unawaited(openOnce(() => widget.onRename(c))),
      onReorder: reorderCategories,
    );
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
              unawaited(
                openOnce(
                  () => widget.onCreate(
                    index == 0 ? CategoryKind.expense : CategoryKind.income,
                  ),
                ),
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
                _kindList(data, CategoryKind.expense),
                _kindList(data, CategoryKind.income),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
