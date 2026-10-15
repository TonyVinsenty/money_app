import 'package:flutter/material.dart';

import 'package:money_app/core/ui/icon_scale.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';

/// Сегментная кнопка, которая не рвёт слова посреди (шаг 8.48).
///
/// Подписи переносятся только целыми словами, шрифт не ужимается. Если самое
/// длинное слово не влезает в сегмент при обычных полях, поля сегмента
/// уменьшаются; если и так не влезает — сегменты встают столбиком. При обычной
/// ширине и шрифте выглядит как обычный [SegmentedButton].
///
/// Ширину слов меряем по подписям-`Text` (с `data`); сегменты с другим видом
/// подписи в замере не участвуют.
class AppSegmentedButton<T> extends StatelessWidget {
  const AppSegmentedButton({
    super.key,
    required this.segments,
    required this.selected,
    required this.onSelectionChanged,
    this.style,
  });

  final List<ButtonSegment<T>> segments;
  final Set<T> selected;
  final void Function(Set<T>)? onSelectionChanged;
  final ButtonStyle? style;

  /// Ширина самого длинного слова среди подписей и значка рядом с ним.
  double _longestSegment(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final textStyle = Theme.of(context).textTheme.labelLarge;
    final iconWidth = 18 * iconScaleOf(context) + AppSpacing.s;
    var longest = 0.0;
    for (final segment in segments) {
      final label = segment.label;
      if (label is! Text || label.data == null) continue;
      for (final word in label.data!.split(RegExp(r'\s+'))) {
        final painter = TextPainter(
          text: TextSpan(text: word, style: textStyle),
          textDirection: Directionality.of(context),
          textScaler: scaler,
        )..layout();
        final width = painter.width + (segment.icon == null ? 0 : iconWidth);
        painter.dispose();
        if (width > longest) longest = width;
      }
    }
    return longest;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final word = _longestSegment(context);
        // Запас на рамки между сегментами.
        final available = constraints.maxWidth - segments.length;
        double needed(double padding) => segments.length * (word + 2 * padding);
        var axis = Axis.horizontal;
        ButtonStyle? effective = style;
        if (needed(AppSpacing.m) > available) {
          if (needed(AppSpacing.xs) <= available) {
            effective = const ButtonStyle(
              padding: WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              ),
            ).merge(style);
          } else {
            axis = Axis.vertical;
          }
        }
        return SegmentedButton<T>(
          showSelectedIcon: false,
          segments: segments,
          selected: selected,
          onSelectionChanged: onSelectionChanged,
          direction: axis,
          style: effective,
        );
      },
    );
  }
}
