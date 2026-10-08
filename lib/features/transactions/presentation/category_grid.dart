import 'package:flutter/material.dart';
import 'package:money_app/core/ui/category_icon_view.dart';
import 'package:money_app/features/categories/domain/category.dart';

/// Сетка плиток «иконка + название» в три колонки.
///
/// Это sliver (кусок прокручиваемого списка): кладётся внутрь `CustomScrollView`
/// рядом с другими кусками. Общая для выбора категории и подкатегории в быстром
/// вводе и в правке операции. Список [categories] уже отфильтрован и упорядочен
/// вызывающим; тап по плитке вызывает [onSelected].
///
/// Если задан [onSkip], первой плиткой идёт «Без подкатегории»: так выбор
/// подкатегории необязателен.
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

  /// Тап по плитке «Без подкатегории»; без него такой плитки нет.
  final VoidCallback? onSkip;

  /// Подпись плитки пропуска; по умолчанию — [skipLabel].
  final String skipText;

  static const skipLabel = 'Без подкатегории';

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
              skipIcon: Icons.remove_circle_outline,
              onTap: skip,
              isSkip: true,
            );
          }
          final category = categories[index - offset];
          return _CategoryTile(
            label: category.name,
            iconKey: category.iconKey,
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
    required this.onTap,
    this.iconKey,
    this.skipIcon,
    this.isSkip = false,
  });

  final String label;

  /// Ключ значка категории; у плитки «Без подкатегории» его нет.
  final String? iconKey;
  final IconData? skipIcon;
  final VoidCallback onTap;

  /// Плитка «Без подкатегории»: контурная, а не залитая, чтобы не выглядеть
  /// как обычная подкатегория.
  final bool isSkip;

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
        color: isSkip ? Colors.transparent : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            // foregroundDecoration, а не decoration: рамка рисуется поверх
            // содержимого и не отнимает у него места (в отличие от
            // decoration, где Container сам добавляет ширину рамки к
            // отступам — тогда двум строкам названия не хватало бы высоты).
            foregroundDecoration: isSkip
                ? BoxDecoration(
                    border: Border.all(color: scheme.outline),
                    borderRadius: BorderRadius.circular(16),
                  )
                : null,
            padding: const EdgeInsets.symmetric(
              horizontal: 4,
              vertical: _verticalPadding,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ExcludeSemantics(
                  child: skipIcon != null
                      ? Icon(
                          skipIcon,
                          size: _iconSize,
                          color: scheme.onSurfaceVariant,
                        )
                      : CategoryIconView(
                          iconKey,
                          size: _iconSize,
                          color: scheme.primary,
                        ),
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
