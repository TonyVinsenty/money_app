import 'package:flutter/material.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';

/// Единый заголовок карточки (ADR 0013, п. 3; design-style.md, 8.4):
/// `titleMedium`, вес 600, слева; справа по желанию одно действие.
/// Суммы в заголовок не кладём: они идут строкой ниже. Длинный заголовок
/// переносится на следующую строку, а не обрезается.
class CardHeader extends StatelessWidget {
  const CardHeader(this.title, {this.trailing, super.key});

  final String title;

  /// Не больше одного действия справа (значок-кнопка или меню).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Semantics(
      header: true,
      child: Text(
        title,
        textAlign: TextAlign.start,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
    final trailing = this.trailing;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.m),
      child: trailing == null
          ? Align(alignment: AlignmentDirectional.centerStart, child: text)
          : Row(
              children: [
                Expanded(child: text),
                trailing,
              ],
            ),
    );
  }
}
