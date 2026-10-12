import 'package:flutter/material.dart';
import 'package:money_app/core/ui/font_scale.dart';
import 'package:money_app/features/transactions/domain/suggest_categories.dart';

/// Ряд умных подсказок над сеткой категорий: до трёх чипов
/// «Продукты · Пятёрочка» без заголовка. Тап по чипу сохраняет операцию.
///
/// При обычном шрифте чипы лежат в [Wrap]: на узком экране переносятся на
/// следующую строку, длинный текст чипа переносится внутри него. С масштаба
/// [twoLineRowScale] (130 %) — одна строка с прокруткой вбок: столбик чипов
/// занимал бы полэкрана и уводил сетку вниз (решение пользователя 2026-10-11,
/// вопрос 6 этапа 7).
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
    final oneLine = useTwoLineRows(context);
    // Один узел для скринридера: сам чип. Озвучку задаёт semanticsLabel
    // текста; значок только для глаз.
    final chips = [
      for (final s in suggestions)
        ActionChip(
          avatar: const ExcludeSemantics(child: Icon(Icons.bolt, size: 18)),
          // В строке с прокруткой текст не переносится: чип просто длиннее.
          label: Text(
            labelOf(s),
            semanticsLabel: spokenOf(s),
            maxLines: oneLine ? 1 : null,
            softWrap: !oneLine,
          ),
          onPressed: () => onSelected(s),
        ),
    ];
    if (oneLine) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              for (var i = 0; i < chips.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                chips[i],
              ],
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Wrap(spacing: 8, runSpacing: 8, children: chips),
    );
  }
}
