import 'package:flutter/material.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/presentation/category_grid.dart';

/// Итог выбора на экране подкатегорий: `subcategory == null` — «Без
/// подкатегории». Отдельный класс нужен, чтобы отличить этот ответ от «Назад»
/// (тогда `Navigator.pop` вернёт просто `null`, а не такой объект).
final class SubcategoryChoice {
  const SubcategoryChoice(this.subcategory);

  final Category? subcategory;
}

/// Выбор подкатегории при правке операции.
///
/// Сетка живых подкатегорий категории [parent] уже загружена вызывающим
/// ([subcategories]); первой плиткой идёт «Без подкатегории». Тап по плитке
/// закрывает экран и возвращает [SubcategoryChoice]; «Назад» возвращает `null`
/// и ничего не меняет. Сохраняет операцию не этот экран, а обычная кнопка
/// «Сохранить» на экране правки.
class EditSubcategoryPickerScreen extends StatelessWidget {
  const EditSubcategoryPickerScreen({
    required this.parent,
    required this.subcategories,
    super.key,
  });

  final Category parent;
  final List<Category> subcategories;

  static const noSubcategoryLabel = 'Без подкатегории';

  @override
  Widget build(BuildContext context) {
    void choose(Category? subcategory) =>
        Navigator.of(context).pop(SubcategoryChoice(subcategory));

    return Scaffold(
      appBar: AppBar(title: Text(parent.name)),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            const SliverPadding(padding: EdgeInsets.only(top: 16)),
            CategoryGrid(
              categories: [
                for (final c in subcategories)
                  if (!c.isArchived) c,
              ],
              onSelected: choose,
              onSkip: () => choose(null),
              skipText: noSubcategoryLabel,
            ),
          ],
        ),
      ),
    );
  }
}
