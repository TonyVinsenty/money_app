import 'package:flutter/material.dart';
import 'package:money_app/core/format/date_format.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/async_view.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Карточка итога за месяц по одному типу операций: «Расходы» или «Доходы».
///
/// Расход и доход — обе карточки с рамкой (`Card.outlined`), без заливки.
/// Подписи нейтральные: цвет и знак («минус» или «+») есть только у суммы. Пустое
/// состояние и ошибка цветом типа не окрашиваются.
///
/// Виджет не знает, откуда берётся сумма: её приносит [total] (поток из
/// `lib/app`, см. ADR 0002).
class MonthSummaryCard extends StatelessWidget {
  const MonthSummaryCard({
    required this.type,
    required this.total,
    required this.month,
    super.key,
  });

  /// Расход или доход: от него зависят заголовок, знак, цвет и вид карточки.
  final TransactionType type;

  /// Итог за [month]. Поток должен быть один и тот же между перерисовками
  /// (его создаёт вызывающий), иначе подписка начнётся заново.
  final Stream<Money> total;

  /// Любой день показываемого месяца: из него берётся название месяца.
  final DateOnly month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isExpense = type == TransactionType.expense;
    final accent = isExpense
        ? context.appColors.expense
        : context.appColors.income;
    final title = isExpense ? 'Расходы' : 'Доходы';
    // Минус — знак U+2212, а не дефис: в тексте он ровнее и не путается с тире.
    final sign = isExpense ? '\u2212' : '+';
    final caption = '$title за ${formatMonthName(month)}';
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    final body = AsyncView<Money>(
      stream: total,
      errorBuilder: (context, error) => Row(
        children: [
          Icon(Icons.error_outline, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Не удалось посчитать ${title.toLowerCase()} за месяц',
              style: muted,
            ),
          ),
        ],
      ),
      // Пока первого значения нет, AsyncView не показывает пустое состояние:
      // «пусто» значит «спросили базу, там ноль».
      isEmpty: (sum) => sum.minorUnits == 0,
      emptyBuilder: (context) => _lines(
        caption: Text(caption, style: muted),
        value: Text(
          'Пока нет',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
      dataBuilder: (context, sum) {
        // Скринридеру суммы читаем словами, без знака и символа валюты.
        return Semantics(
          label: '$caption: ${spokenMoney(sum)}',
          excludeSemantics: true,
          child: _lines(
            caption: Text(caption, style: muted),
            value: Text(
              '$sign${formatMoney(sum)}',
              style: theme.textTheme.headlineSmall?.copyWith(color: accent),
            ),
          ),
        );
      },
    );

    // Внешний отступ у Card по умолчанию 4 dp: обнуляем, чтобы карточка
    // совпала с отступом экрана. Скругление 16 dp задаём явно (у Card — 12).
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: scheme.outlineVariant),
    );
    final content = Padding(padding: const EdgeInsets.all(16), child: body);

    return Card.outlined(margin: EdgeInsets.zero, shape: shape, child: content);
  }

  /// Подпись сверху, значение под ней. Текст переносится сам: длинная сумма
  /// уходит на вторую строку, а не сжимается (FittedBox здесь не используем).
  static Widget _lines({required Widget caption, required Widget value}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [caption, const SizedBox(height: 4), value],
    );
  }
}
