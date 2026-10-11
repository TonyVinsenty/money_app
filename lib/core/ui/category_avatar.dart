import 'package:flutter/material.dart';
import 'package:money_app/core/ui/category_icon_view.dart';

/// Значок категории в кружке 40 dp. Без [color] кружок нейтральный (как в
/// «Истории»); цвет заливки нужен, например, для цветной категории.
/// От скринридера скрыт: подпись даёт строка вокруг.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar(this.iconKey, {this.color, super.key});

  /// Ключ `Category.iconKey`; `null` - запасной значок.
  final String? iconKey;

  /// Цвет заливки; `null` - нейтральный.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color ?? Theme.of(context).colorScheme.surfaceContainerHighest,
        shape: BoxShape.circle,
      ),
      child: CategoryIconView(iconKey, size: 24),
    );
  }
}
