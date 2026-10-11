import 'package:flutter/material.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/ui/category_avatar.dart';
import 'package:money_app/core/ui/masked_amount.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';

/// Строка операции: аватар категории, [title] («Категория · Подкатегория»),
/// необязательная вторая строка [subtitle] и сумма справа со знаком и цветом
/// дохода/расхода. Скринридер читает строку одним узлом с подписью
/// [semanticLabel]; без [onTap] строка не кнопка.
class OperationTile extends StatelessWidget {
  const OperationTile({
    required this.title,
    required this.amount,
    required this.isIncome,
    required this.semanticLabel,
    this.subtitle,
    this.iconKey,
    this.categoryName,
    this.avatarColor,
    this.onTap,
    this.horizontalPadding = AppSpacing.l,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Money amount;
  final bool isIncome;
  final String semanticLabel;
  final String? iconKey;

  /// Название категории для буквы в аватаре (ключ «Другое»).
  final String? categoryName;
  final Color? avatarColor;
  final VoidCallback? onTap;

  /// Боковой отступ: в карточке меньше, чем в списке во всю ширину.
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = isIncome
        ? context.appColors.income
        : context.appColors.expense;
    final sign = isIncome ? '+' : String.fromCharCode(0x2212);
    final subtitle = this.subtitle;

    final content = ConstrainedBox(
      // Зона нажатия не ниже 48 dp; при крупном шрифте строка растёт сама.
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: horizontalPadding,
          vertical: AppSpacing.s,
        ),
        child: Row(
          children: [
            CategoryAvatar(iconKey, name: categoryName, color: avatarColor),
            const SizedBox(width: AppSpacing.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.m),
            // Сумма не шире 45% экрана: длинная при крупном шрифте уменьшается.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.45,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: MaskedAmount(
                  '$sign${formatMoney(amount)}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      container: true,
      label: semanticLabel,
      button: onTap != null,
      onTap: onTap,
      excludeSemantics: true,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: AppRadius.borderM,
              child: content,
            ),
    );
  }
}
