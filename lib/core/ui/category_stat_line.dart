import 'package:flutter/material.dart';
import 'package:money_app/core/ui/font_scale.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';

/// Стиль названия в строках категорий «Аналитики».
TextStyle? categoryNameStyle(ThemeData theme) => theme.textTheme.bodyLarge;

/// Стиль суммы в строках категорий «Аналитики»: цвет задаёт вызывающий.
TextStyle? categoryAmountStyle(ThemeData theme, {Color? color}) => theme
    .textTheme
    .titleMedium
    ?.copyWith(color: color, fontWeight: FontWeight.w600);

/// Стиль второй строки (процент, разница, число операций).
TextStyle? categorySubtitleStyle(ThemeData theme) => theme.textTheme.bodySmall
    ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

/// Тело строки категории, одинаковое во всех списках «Аналитики»: аватар,
/// название слева, сумма справа, под названием вторая строка. При крупном
/// шрифте сумма уходит под название (ужимается, а не рвётся посреди числа).
/// Отступа по краям нет: аватар стоит вровень с заголовком карточки.
class CategoryStatLine extends StatelessWidget {
  const CategoryStatLine({
    required this.leading,
    required this.name,
    this.amount,
    this.subtitle,
    this.nameMaxLines = 2,
    super.key,
  });

  final Widget leading;
  final String name;

  /// Сумма, уже оформленная [categoryAmountStyle]; `null` — суммы нет.
  final Widget? amount;

  /// Вторая строка, оформленная [categorySubtitleStyle].
  final Widget? subtitle;
  final int nameMaxLines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final twoLine = useTwoLineRows(context);
    final amount = this.amount;
    final subtitle = this.subtitle;
    final nameText = Text(
      name,
      style: categoryNameStyle(theme),
      maxLines: nameMaxLines,
      overflow: TextOverflow.ellipsis,
    );
    final fitted = amount == null
        ? null
        : FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerEnd,
            child: amount,
          );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            ExcludeSemantics(child: leading),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  nameText,
                  if (twoLine && fitted != null)
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: amount,
                      ),
                    ),
                  ?subtitle,
                ],
              ),
            ),
            if (!twoLine && fitted != null) ...[
              const SizedBox(width: AppSpacing.s),
              Flexible(child: fitted),
            ],
          ],
        ),
      ),
    );
  }
}
