import 'package:flutter/material.dart';
import 'package:money_app/features/transactions/domain/suggest_categories.dart';

/// Ряд умных подсказок над сеткой категорий: до трёх чипов
/// «Продукты · Пятёрочка» без заголовка. Тап по чипу сохраняет операцию.
///
/// Чипы лежат в [Wrap]: при узком экране и крупном шрифте они переносятся на
/// следующую строку, а слишком длинный текст чипа переносится внутри него,
/// поэтому ничего не обрезается.
class SuggestionRow extends StatelessWidget {
  const SuggestionRow({
    required this.suggestions,
    required this.onSelected,
    super.key,
  });

  final List<CategorySuggestion> suggestions;
  final ValueChanged<CategorySuggestion> onSelected;

  /// Текст чипа: «Продукты · Пятёрочка» или просто «Продукты».
  static String labelOf(CategorySuggestion s) => s.subcategory == null
      ? s.category.name
      : '${s.category.name} · ${s.subcategory!.name}';

  /// Озвучка: «Сохранить: Продукты, Пятёрочка».
  static String spokenOf(CategorySuggestion s) => s.subcategory == null
      ? 'Сохранить: ${s.category.name}'
      : 'Сохранить: ${s.category.name}, ${s.subcategory!.name}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final s in suggestions)
            // Один узел для скринридера: сам чип. Озвучку задаёт
            // semanticsLabel текста; значок только для глаз.
            ActionChip(
              avatar: const ExcludeSemantics(child: Icon(Icons.bolt, size: 18)),
              // Текст чипа может быть длинным: пусть переносится.
              label: Text(labelOf(s), semanticsLabel: spokenOf(s)),
              onPressed: () => onSelected(s),
            ),
        ],
      ),
    );
  }
}
