import 'package:flutter/material.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/ui/category_avatar.dart';
import 'package:money_app/core/ui/font_scale.dart';
import 'package:money_app/core/ui/masked_amount.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';

/// Строка операции: аватар категории, [title] («Категория · Подкатегория»),
/// необязательная вторая строка [subtitle] и сумма справа со знаком и цветом
/// дохода/расхода; при крупном шрифте (от 130 %) или узкой колонке текста
/// (меньше [minTextColumnWidth]) сумма встаёт под название.
/// Скринридер читает строку одним узлом с подписью [semanticLabel]; без
/// [onTap] строка не кнопка.
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

  /// Ключ текста суммы (для тестов раскладки).
  static const amountKey = ValueKey('operation-tile-amount');

  /// Боковой отступ: в карточке меньше, чем в списке во всю ширину.
  final double horizontalPadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = isIncome
        ? context.appColors.income
        : context.appColors.expense;
    final sign = isIncome ? '+' : String.fromCharCode(0x2212);
    final amountLabel = '$sign${formatMoney(amount)}';
    final amountStyle = theme.textTheme.titleMedium?.copyWith(
      color: accent,
      fontWeight: FontWeight.w600,
    );
    final amountText = MaskedAmount(
      amountLabel,
      textKey: amountKey,
      style: amountStyle,
    );
    final scaler = MediaQuery.textScalerOf(context);
    final scaleTwoLine = useTwoLineRows(context);
    final maxAmountWidth = MediaQuery.sizeOf(context).width * 0.45;
    final content = LayoutBuilder(
      builder: (context, constraints) {
        // Двухэтажный вид: от крупного шрифта или когда рядом с суммой на
        // колонку текста остаётся меньше [minTextColumnWidth] (узкий экран).
        var twoLine = scaleTwoLine;
        if (!twoLine) {
          final painter = TextPainter(
            text: TextSpan(text: amountLabel, style: amountStyle),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
          )..layout();
          final amountWidth = painter.width < maxAmountWidth
              ? painter.width
              : maxAmountWidth;
          painter.dispose();
          final textWidth =
              constraints.maxWidth -
              2 * horizontalPadding -
              _avatarWidth -
              2 * AppSpacing.m -
              amountWidth;
          twoLine = textWidth < minTextColumnWidth;
        }
        return _buildRow(context, twoLine, amountText, maxAmountWidth);
      },
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

  /// Ширина аватара категории.
  static const double _avatarWidth = 40;

  /// Меньше такой ширины колонки текста строка становится двухэтажной.
  static const double minTextColumnWidth = 160;

  Widget _buildRow(
    BuildContext context,
    bool twoLine,
    Widget amountText,
    double maxAmountWidth,
  ) {
    final theme = Theme.of(context);
    final subtitle = this.subtitle;
    final texts = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyLarge,
        ),
        // Крупный шрифт: сумма под названием в полный размер. Уменьшается
        // только сумма шире всей строки (иначе число разорвалось бы).
        if (twoLine)
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: amountText,
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
    );

    return ConstrainedBox(
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
            Expanded(child: texts),
            if (!twoLine) ...[
              const SizedBox(width: AppSpacing.m),
              // Сумма не шире 45% экрана: длинная уменьшается.
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxAmountWidth),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: amountText,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
