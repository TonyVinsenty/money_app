import 'package:flutter/material.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/ui/font_scale.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/analytics/domain/period_summary.dart';

/// Карточка итогов периода: «Расходы», «Доходы», «Баланс» и число операций.
///
/// Подписи нейтральные: цвет и знак есть только у суммы. Расходы — со знаком
/// «\u2212» и цветом расхода, доходы — с «+» и цветом дохода, баланс — знак и
/// цвет по знаку, ноль нейтральный и без знака. При крупном шрифте подпись и
/// сумма встают друг под другом, сумма при этом переносится, а не обрезается.
class PeriodSummaryCard extends StatelessWidget {
  const PeriodSummaryCard({required this.summary, super.key});

  final PeriodSummary summary;

  /// Ключи строк: на них опираются тесты.
  static const expenseKey = ValueKey('period-summary-expense');
  static const incomeKey = ValueKey('period-summary-income');
  static const balanceKey = ValueKey('period-summary-balance');
  static const countKey = ValueKey('period-summary-count');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.appColors;
    final balance = summary.balance;
    final stacked = fontScaleOf(context) > 1.3;

    final balanceColor = balance.isZero
        ? scheme.onSurface
        : balance.isNegative
        ? colors.expense
        : colors.income;
    // Отрицательную сумму formatMoney уже пишет со знаком «\u2212».
    final balanceText = balance.isNegative || balance.isZero
        ? formatMoney(balance)
        : '+${formatMoney(balance)}';
    final balanceSpoken = balance.isZero || balance.isNegative
        ? spokenMoney(balance)
        : 'плюс ${spokenMoney(balance)}';

    // Рамка и скругление 16 dp, как у карточек «Главной» и кольца.
    return Card.outlined(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Line(
              key: expenseKey,
              title: 'Расходы',
              text: '\u2212${formatMoney(summary.expense)}',
              spoken: 'минус ${spokenMoney(summary.expense)}',
              color: colors.expense,
              stacked: stacked,
            ),
            const SizedBox(height: 12),
            _Line(
              key: incomeKey,
              title: 'Доходы',
              text: '+${formatMoney(summary.income)}',
              spoken: 'плюс ${spokenMoney(summary.income)}',
              color: colors.income,
              stacked: stacked,
            ),
            const SizedBox(height: 12),
            _Line(
              key: balanceKey,
              title: 'Баланс',
              text: balanceText,
              spoken: balanceSpoken,
              color: balanceColor,
              stacked: stacked,
            ),
            const SizedBox(height: 12),
            Text(
              'Операций: ${summary.count}',
              key: countKey,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Строка «подпись — сумма»: в ряд или (при крупном шрифте) друг под другом.
/// Скринридер читает её одним узлом, сумму словами.
class _Line extends StatelessWidget {
  const _Line({
    required this.title,
    required this.text,
    required this.spoken,
    required this.color,
    required this.stacked,
    super.key,
  });

  final String title;
  final String text;
  final String spoken;
  final Color color;
  final bool stacked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = Text(
      title,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final amount = Text(
      text,
      textAlign: stacked ? TextAlign.start : TextAlign.end,
      style: theme.textTheme.titleLarge?.copyWith(color: color),
    );
    return Semantics(
      container: true,
      label: '$title, $spoken',
      excludeSemantics: true,
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [label, const SizedBox(height: 4), amount],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                label,
                const SizedBox(width: 12),
                Expanded(child: amount),
              ],
            ),
    );
  }
}
