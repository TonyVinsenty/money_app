import 'package:flutter/material.dart';
import 'package:money_app/core/ui/category_icon_view.dart';
import 'package:money_app/core/ui/icon_scale.dart';

/// Значок категории в кружке 40 dp. Без [color] кружок нейтральный (как в
/// «Истории»); цвет заливки нужен, например, для цветной категории.
/// От скринридера скрыт: подпись даёт строка вокруг.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar(this.iconKey, {this.name, this.color, super.key});

  /// Ключ `Category.iconKey`; `null` - запасной значок.
  final String? iconKey;

  /// Название категории: для ключа «Другое» в кружке рисуется его первая буква.
  final String? name;

  /// Цвет заливки; `null` - нейтральный.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fill = color;
    final k = iconScaleOf(context);
    return Container(
      width: 40 * k,
      height: 40 * k,
      decoration: BoxDecoration(
        color: fill ?? Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: CategoryIconView(
        iconKey,
        name: name,
        size: 24 * k,
        color: fill == null ? null : categoryAvatarForeground(fill),
      ),
    );
  }
}

const Color _lightGlyph = Color(0xFFFFFFFF);
const Color _darkGlyph = Color(0xFF212121);

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// Цвет значка на цветной заливке: белый или тёмный - тот, что контрастнее.
Color categoryAvatarForeground(Color fill) =>
    _contrast(_lightGlyph, fill) >= _contrast(_darkGlyph, fill)
    ? _lightGlyph
    : _darkGlyph;
