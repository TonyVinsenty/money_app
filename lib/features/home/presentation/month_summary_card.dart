import 'package:flutter/material.dart';
import 'package:money_app/core/format/date_format.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/async_view.dart';
import 'package:money_app/core/ui/font_scale.dart';
import 'package:money_app/core/ui/period_switcher.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Боковой отступ экрана «Главной» и внутренний отступ карточки, dp. Нужны,
/// чтобы прикинуть ширину колонок (см. [_fitsInRow]).
const double _screenInset = 16;
const double _cardPadding = 16;

/// Минимальная ширина содержимого карточки при шрифте 100 %, при которой
/// «Расходы» и «Доходы» стоят в ряд, dp. На телефоне 360 dp содержимое имеет
/// 360 - 2 * 16 - 2 * 16 = 296 dp: в ряд.
const double _minRowWidth = 240;

/// Хватает ли ширины содержимого карточки [contentWidth] при масштабе шрифта
/// [textScale], чтобы «Расходы» и «Доходы» стояли в ряд. Этим же порогом
/// пользуется расчёт размера кольца (`chartRingSize`).
bool summaryFitsInRow(double contentWidth, double textScale) =>
    contentWidth / textScale >= _minRowWidth;

/// Грубая высота карточки итогов, dp: отступы, заголовок и колонки (ряд или
/// столбик, как решает [summaryFitsInRow]). В столбике сумма может перенестись
/// на вторую строку, поэтому для неё берём две строки.
double estimateSummaryHeight(double contentWidth, double textScale) {
  final inRow = summaryFitsInRow(contentWidth, textScale);
  const rowColumn = 20 + 4 + 28; // подпись, зазор, сумма в одну строку
  const stackedColumn = 20 + 4 + 2 * 28;
  final columns = inRow
      ? rowColumn * textScale
      : 2 * stackedColumn * textScale + 25;
  // Заголовок — переключатель месяца: стрелки 48 dp, но не ниже подписи.
  final header = 48 > 22 * textScale ? 48.0 : 22 * textScale;
  return 2 * _cardPadding + header + 4 + columns;
}

/// Одна компактная карточка итогов за месяц: заголовок-переключатель «‹ Октябрь 2026 ›», под ним
/// две колонки через тонкий разделитель — «Расходы» и «Доходы».
///
/// Подписи нейтральные: цвет и знак («минус» или «+») есть только у суммы.
/// Пустое состояние и ошибка цветом типа не окрашиваются. Если ширины мало или
/// шрифт крупный, колонки встают друг под другом.
///
/// Виджет не знает, откуда берутся суммы: их приносят [expenses] и [income]
/// (потоки из `lib/app`, см. ADR 0002).
class MonthSummaryCard extends StatelessWidget {
  const MonthSummaryCard({
    required this.expenses,
    required this.income,
    required this.month,
    this.onPreviousMonth,
    this.onNextMonth,
    super.key,
  });

  /// Стрелки «‹» и «›» заголовка; `null` — стрелка недоступна.
  final VoidCallback? onPreviousMonth;
  final VoidCallback? onNextMonth;

  /// Ключи колонок: на них опираются тесты и поиск по дереву.
  static const expenseKey = ValueKey('month-summary-expense');
  static const incomeKey = ValueKey('month-summary-income');

  /// Итоги за [month]. Потоки должны быть одними и теми же между перерисовками
  /// (их создаёт вызывающий), иначе подписка начнётся заново.
  final Stream<Money> expenses;
  final Stream<Money> income;

  /// Любой день показываемого месяца: из него берётся название месяца.
  final DateOnly month;

  /// Ряд или столбик. Ширину содержимого прикидываем по ширине экрана (без
  /// `LayoutBuilder`, чтобы карточка годилась для расчёта по intrinsic-размерам);
  /// шрифт учитываем отдельно: чем он крупнее, тем больше места нужно суммам.
  bool _fitsInRow(BuildContext context) {
    final width =
        MediaQuery.sizeOf(context).width - 2 * _screenInset - 2 * _cardPadding;
    return summaryFitsInRow(width, fontScaleOf(context));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = formatMonthName(month);
    final title = formatMonthTitle(month);
    final inRow = _fitsInRow(context);

    final expenseColumn = _SummaryColumn(
      key: expenseKey,
      type: TransactionType.expense,
      total: expenses,
      monthName: name,
      fit: inRow,
    );
    final incomeColumn = _SummaryColumn(
      key: incomeKey,
      type: TransactionType.income,
      total: income,
      monthName: name,
      fit: inRow,
    );

    final columns = inRow
        ? IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: expenseColumn),
                VerticalDivider(
                  width: 25,
                  thickness: 1,
                  color: scheme.outlineVariant,
                ),
                Expanded(child: incomeColumn),
              ],
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              expenseColumn,
              Divider(height: 25, thickness: 1, color: scheme.outlineVariant),
              incomeColumn,
            ],
          );

    // Внешний отступ у Card по умолчанию 4 dp: обнуляем, чтобы карточка
    // совпала с отступом экрана. Скругление 16 dp задаём явно (у Card — 12).
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: scheme.outlineVariant),
    );
    return Card.outlined(
      margin: EdgeInsets.zero,
      shape: shape,
      child: Padding(
        padding: const EdgeInsets.all(_cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PeriodSwitcher(
              label: title,
              onPrevious: onPreviousMonth,
              onNext: onNextMonth,
              previousTooltip: 'Предыдущий месяц',
              nextTooltip: 'Следующий месяц',
            ),
            const SizedBox(height: 4),
            columns,
          ],
        ),
      ),
    );
  }
}

/// Колонка «Расходы» или «Доходы»: подпись сверху, сумма под ней.
class _SummaryColumn extends StatelessWidget {
  const _SummaryColumn({
    required this.type,
    required this.total,
    required this.monthName,
    required this.fit,
    super.key,
  });

  final TransactionType type;
  final Stream<Money> total;
  final String monthName;

  /// В ряду сумма при нехватке места уменьшается (`FittedBox`), в столбике
  /// ширины хватает, и она просто переносится.
  final bool fit;

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
    final muted = theme.textTheme.bodyMedium?.copyWith(
      color: scheme.onSurfaceVariant,
    );

    Widget lines(Widget value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: muted),
        const SizedBox(height: 4),
        value,
      ],
    );

    return AsyncView<Money>(
      stream: total,
      // Пока первого значения нет, видна только подпись: итог не мигает.
      loadingBuilder: (context) => lines(const SizedBox.shrink()),
      errorBuilder: (context, error) => lines(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
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
      ),
      // «Пусто» значит «спросили базу, там ноль».
      isEmpty: (sum) => sum.minorUnits == 0,
      emptyBuilder: (context) => lines(
        Text(
          'Пока нет',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
      dataBuilder: (context, sum) {
        // В ряду сумма всегда в одну строку: иначе IntrinsicHeight мерил бы её
        // как перенесённую, а FittedBox рисовал бы в одну, и ряд вышел бы
        // высоким с пустотой внутри.
        final amount = Text(
          '$sign${formatMoney(sum)}',
          maxLines: fit ? 1 : null,
          softWrap: !fit,
          style: theme.textTheme.titleLarge?.copyWith(color: accent),
        );
        // Скринридеру колонка читается одним узлом, сумма словами, без знака и
        // символа валюты.
        // container: true нужен, чтобы колонки не склеивались в один узел с
        // карточкой (Card сам собирает узел из потомков).
        return Semantics(
          container: true,
          label: '$title за $monthName: ${spokenMoney(sum)}',
          excludeSemantics: true,
          child: lines(
            fit
                ? FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: amount,
                  )
                : amount,
          ),
        );
      },
    );
  }
}
