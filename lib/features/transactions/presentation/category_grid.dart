import 'package:flutter/material.dart';
import 'package:money_app/core/ui/category_icons.dart';
import 'package:money_app/features/categories/domain/category.dart';

/// Сетка плиток «иконка + название» в три колонки.
///
/// Это sliver (кусок прокручиваемого списка): кладётся внутрь `CustomScrollView`
/// рядом с другими кусками. Общая для выбора категории в быстром вводе и в
/// правке операции. Список [categories] уже отфильтрован и упорядочен
/// вызывающим; тап по плитке вызывает [onSelected].
class CategoryGrid extends StatelessWidget {
  const CategoryGrid({
    required this.categories,
    required this.onSelected,
    super.key,
  });

  final List<Category> categories;
  final ValueChanged<Category> onSelected;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          // Высота плитки растёт с системным шрифтом: считаем её из
          // масштаба текста, а не задаём числом.
          mainAxisExtent: _CategoryTile.extentFor(context),
        ),
        delegate: SliverChildBuilderDelegate((context, index) {
          final category = categories[index];
          return _CategoryTile(
            category: category,
            onTap: () => onSelected(category),
          );
        }, childCount: categories.length),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});

  final Category category;
  final VoidCallback onTap;

  static const _iconSize = 32.0;
  static const _verticalPadding = 12.0;
  static const _gap = 8.0;
  static const _lines = 2;

  /// Стиль названия. Общий для плитки и для расчёта её высоты.
  static TextStyle? _labelStyle(BuildContext context) =>
      Theme.of(context).textTheme.labelLarge;

  /// Высота плитки: иконка + две строки названия с учётом системного масштаба
  /// текста. Не меньше 96 dp, поэтому зона нажатия всегда больше 48 dp.
  static double extentFor(BuildContext context) {
    final style = _labelStyle(context);
    final scaler = MediaQuery.textScalerOf(context);
    final lineHeight =
        scaler.scale(style?.fontSize ?? 14) * (style?.height ?? 1.4);
    final extent =
        _verticalPadding * 2 + _iconSize + _gap + lineHeight * _lines;
    return extent < 96 ? 96 : extent;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: category.name,
      excludeSemantics: true,
      // Тап задан явно: excludeSemantics убирает и действия InkWell внутри.
      onTap: onTap,
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: _verticalPadding,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    categoryIconFor(category.iconKey),
                    size: _iconSize,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: _gap),
                Text(
                  category.name,
                  maxLines: _lines,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: _labelStyle(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
