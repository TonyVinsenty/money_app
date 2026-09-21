import 'dart:async';

import 'package:flutter/material.dart';
import 'package:money_app/core/ui/async_view.dart';
import 'package:money_app/core/ui/category_rule_text.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/presentation/category_actions.dart';
import 'package:money_app/features/categories/presentation/category_list.dart';

/// Подпись над списком: заголовок экрана — имя родителя, а это — что именно
/// в списке.
const subcategoriesSectionTitle = 'Подкатегории';

/// Кнопка создания новой подкатегории.
const subcategoriesAddAction = 'Добавить подкатегорию';

/// Сообщение после отправки в архив.
String subcategoriesArchivedMessage(String name) =>
    'Подкатегория «$name» в архиве';

/// Пояснение первой строкой в развёрнутом архиве.
const subcategoriesArchiveNote =
    'Старые операции по этим подкатегориям сохранены';

/// Пока у категории нет ни одной живой подкатегории.
const subcategoriesEmptyText = 'Подкатегорий пока нет';

/// Экран «Подкатегории» одной категории [parent] (открывается со строки
/// категории на экране «Категории»).
///
/// Живые подкатегории в порядке `sortOrder` (их можно переставлять) и свёрнутый
/// раздел «Архив (N)». Действия те же, что у категорий. Форму создания и
/// переименования открывают колбэки [onCreate] и [onRename], их даёт
/// приложение; пока форма открыта, повторный тап второй не открывает.
class SubcategoriesScreen extends StatefulWidget {
  const SubcategoriesScreen({
    required this.parent,
    required this.categories,
    required this.onCreate,
    required this.onRename,
    super.key,
  });

  final Category parent;
  final CategoriesRepository categories;
  final Future<void> Function() onCreate;
  final Future<void> Function(Category subcategory) onRename;

  @override
  State<SubcategoriesScreen> createState() => _SubcategoriesScreenState();
}

class _SubcategoriesScreenState extends State<SubcategoriesScreen>
    with CategoryActions<SubcategoriesScreen> {
  /// Поток создаём один раз: в `build` каждая перерисовка подписывалась бы
  /// заново.
  ///
  /// Нужен именно `watchAll`: `watchSubcategories` отдаёт только живые, а
  /// архивные подкатегории тоже показываем (раздел «Архив»).
  late final Stream<List<Category>> _stream;

  @override
  CategoriesRepository get categoriesRepository => widget.categories;

  @override
  String archivedMessage(String name) => subcategoriesArchivedMessage(name);

  @override
  void initState() {
    super.initState();
    _stream = widget.categories.watchAll();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.parent.name)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => unawaited(openOnce(widget.onCreate)),
        icon: const Icon(Icons.add),
        label: const Text(subcategoriesAddAction),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Semantics(
                header: true,
                child: Text(
                  subcategoriesSectionTitle,
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
            Expanded(
              child: AsyncView<List<Category>>(
                stream: _stream,
                errorBuilder: (context, error) => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      subcategoriesLoadErrorText,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                dataBuilder: (context, data) => CategoryList(
                  categories: data,
                  belongs: (c) => c.parentId == widget.parent.id,
                  archiveKey: 'archive-subcategories',
                  archiveNote: subcategoriesArchiveNote,
                  emptyText: subcategoriesEmptyText,
                  onArchive: (c) => unawaited(archiveCategory(c)),
                  onRestore: (c) => unawaited(restoreCategory(c)),
                  onRename: (c) =>
                      unawaited(openOnce(() => widget.onRename(c))),
                  onReorder: reorderCategories,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
