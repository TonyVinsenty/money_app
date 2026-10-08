import 'package:flutter/material.dart';
import 'package:money_app/core/ui/category_icons.dart';

/// Значок категории: иконка Material или символ (буква, цифра).
///
/// Единственное место, где ключ `Category.iconKey` превращается в картинку.
/// Размер и цвет по умолчанию берутся из окружения, как у обычного [Icon].
/// Подпись для скринридера даёт строка или плитка вокруг, поэтому сам значок
/// скрыт от семантики. `null` и неизвестный ключ рисуют запасной значок.
class CategoryIconView extends StatelessWidget {
  const CategoryIconView(this.iconKey, {super.key, this.size, this.color});

  final String? iconKey;
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final key = iconKey;
    final glyph = key == null ? null : categoryGlyphFor(key);
    final iconTheme = IconTheme.of(context);
    final side = size ?? iconTheme.size ?? 24.0;
    final tint = color ?? iconTheme.color;
    if (glyph == null) {
      return ExcludeSemantics(
        child: Icon(
          key == null ? fallbackCategoryIcon : categoryIconFor(key),
          size: side,
          color: color,
        ),
      );
    }
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: side,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            glyph,
            textScaler: TextScaler.noScaling,
            style: TextStyle(
              fontSize: side * 0.8,
              height: 1,
              fontWeight: FontWeight.bold,
              color: tint,
            ),
          ),
        ),
      ),
    );
  }
}
