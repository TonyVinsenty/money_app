import 'package:flutter/material.dart';
import 'package:money_app/core/ui/category_icons.dart';
import 'package:money_app/features/categories/domain/category.dart';

/// Сетка плиток «иконка + название» в три колонки.
///
/// Это sliver (кусок прокручиваемого списка): кладётся внутрь `CustomScrollView`
/// рядом с другими кусками. Общая для выбора категории и подкатегории в быстром
/// вводе и в правке операции. Список [categories] уже отфильтрован и упорядочен
/// вызывающим; тап по плитке вызывает [onSelected].
///
/// Если задан [onSkip], первой плиткой идёт «Пропустить» (без категории):
/// так выбор подкатегории необязателен.
class CategoryGrid extends StatelessWidget {
  const CategoryGrid({
    required this.categories,
    required this.onSelected,
    this.onSkip,
    this.skipText = skipLabel,
    super.key,
  });

  final List<Category> categories;
  final ValueChanged<Category> onSelected;

  /// Тап по плитке «Пропустить»; без него такой плитки нет.
  final VoidCallback? onSkip;

  /// Подпись плитки пропуска: в правке операции это «Без подкатегории».
  final String skipText;

  static const skipLabel = 'Пропустить';

  @override
  Widget build(BuildContext context) {
    final skip = onSkip;
    final offset = skip == null ? 0 : 1;
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
          if (skip != null && index == 0) {
            return _CategoryTile(
              label: skipText,
              icon: Icons.arrow_forward,
              onTap: skip,
            );
          }
          final category = categories[index - offset];
          return _CategoryTile(
            label: category.name,
            icon: categoryIconFor(category.iconKey),
            onTap: () => onSelected(category),
          );
        }, childCount: categories.length + offset),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
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
      label: label,
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
                  child: Icon(icon, size: _iconSize, color: scheme.primary),
                ),
                const SizedBox(height: _gap),
                Text(
                  label,
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
