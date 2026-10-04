import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

/// Семантические цвета приложения: «расход» (красная гамма) и «доход» (зелёная).
///
/// Цвет не должен быть единственным носителем смысла: при показе суммы всегда
/// добавляйте знак («\u2212»/«+») или иконку. Так сумму поймёт и человек, который
/// не различает красный и зелёный. Знак в поле ввода суммы — `AmountField`;
/// в списках знак добавляет каждый экран сам.
///
/// Оттенки подобраны так, чтобы контраст с фоном `ColorScheme.surface`
/// своей темы был не ниже 4.5:1 (WCAG AA для текста); это проверяет тест.
///
/// Кнопки «Доход» и «Расход» — отдельные пары «заливка + текст»
/// ([expenseAction]/[onExpenseAction], [incomeAction]/[onIncomeAction]).
/// Они глубокие в обеих темах, поэтому текст на них светлый. Контраст каждой
/// пары тоже проверяет тест.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.expense,
    required this.income,
    required this.expenseAction,
    required this.onExpenseAction,
    required this.incomeAction,
    required this.onIncomeAction,
    required this.chartPalette,
    required this.chartOther,
  });

  /// Цвета для светлой темы.
  static const AppColors light = AppColors(
    expense: Color(0xFFB3261E),
    income: Color(0xFF1B6E3A),
    expenseAction: Color(0xFFB3261E),
    onExpenseAction: Color(0xFFFFFFFF),
    incomeAction: Color(0xFF1B6E3A),
    onIncomeAction: Color(0xFFFFFFFF),
    chartPalette: [
      Color(0xFF1E63C4),
      Color(0xFFC25400),
      Color(0xFF7B4FC4),
      Color(0xFF00838F),
      Color(0xFF8D6E00),
      Color(0xFFAD1F8A),
      Color(0xFF283593),
      Color(0xFF7A5230),
    ],
    chartOther: Color(0xFF757575),
  );

  /// Цвета для тёмной темы (светлее, чтобы читались на тёмном фоне).
  static const AppColors dark = AppColors(
    expense: Color(0xFFFF8A80),
    income: Color(0xFF7BD88F),
    expenseAction: Color(0xFF8C1D18),
    onExpenseAction: Color(0xFFF9DEDC),
    incomeAction: Color(0xFF1A5233),
    onIncomeAction: Color(0xFFC8EED2),
    chartPalette: [
      Color(0xFF8AB4F8),
      Color(0xFFFFB06B),
      Color(0xFFC3A6FF),
      Color(0xFF4DD0E1),
      Color(0xFFE6C34A),
      Color(0xFFF48FD0),
      Color(0xFF7986CB),
      Color(0xFFD7A97E),
    ],
    chartOther: Color(0xFF8F8F8F),
  );

  final Color expense;
  final Color income;

  /// Заливка кнопки «Расход».
  final Color expenseAction;

  /// Текст и знак на кнопке «Расход».
  final Color onExpenseAction;

  /// Заливка кнопки «Доход».
  final Color incomeAction;

  /// Текст и знак на кнопке «Доход».
  final Color onIncomeAction;

  /// Цвета секторов диаграммы: ровно 8, цвет определяется местом сектора
  /// (самый крупный сектор берёт первый цвет), а не категорией. Среди них нет
  /// смысловых красного и зелёного, контраст с `surface` не ниже 3:1.
  final List<Color> chartPalette;

  /// Цвет сектора «Остальное» (серый, не совпадает с [chartPalette]).
  final Color chartOther;

  @override
  AppColors copyWith({
    Color? expense,
    Color? income,
    Color? expenseAction,
    Color? onExpenseAction,
    Color? incomeAction,
    Color? onIncomeAction,
    List<Color>? chartPalette,
    Color? chartOther,
  }) {
    return AppColors(
      expense: expense ?? this.expense,
      income: income ?? this.income,
      expenseAction: expenseAction ?? this.expenseAction,
      onExpenseAction: onExpenseAction ?? this.onExpenseAction,
      incomeAction: incomeAction ?? this.incomeAction,
      onIncomeAction: onIncomeAction ?? this.onIncomeAction,
      chartPalette: chartPalette ?? this.chartPalette,
      chartOther: chartOther ?? this.chartOther,
    );
  }

  @override
  AppColors lerp(covariant ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      expense: Color.lerp(expense, other.expense, t)!,
      income: Color.lerp(income, other.income, t)!,
      expenseAction: Color.lerp(expenseAction, other.expenseAction, t)!,
      onExpenseAction: Color.lerp(onExpenseAction, other.onExpenseAction, t)!,
      incomeAction: Color.lerp(incomeAction, other.incomeAction, t)!,
      onIncomeAction: Color.lerp(onIncomeAction, other.onIncomeAction, t)!,
      chartPalette: [
        for (var i = 0; i < chartPalette.length; i++)
          Color.lerp(
            chartPalette[i],
            i < other.chartPalette.length ? other.chartPalette[i] : null,
            t,
          )!,
      ],
      chartOther: Color.lerp(chartOther, other.chartOther, t)!,
    );
  }

  @override
  bool operator ==(Object other) {
    return other.runtimeType == runtimeType &&
        other is AppColors &&
        other.expense == expense &&
        other.income == income &&
        other.expenseAction == expenseAction &&
        other.onExpenseAction == onExpenseAction &&
        other.incomeAction == incomeAction &&
        other.onIncomeAction == onIncomeAction &&
        listEquals(other.chartPalette, chartPalette) &&
        other.chartOther == chartOther;
  }

  @override
  int get hashCode => Object.hash(
    expense,
    income,
    expenseAction,
    onExpenseAction,
    incomeAction,
    onIncomeAction,
    Object.hashAll(chartPalette),
    chartOther,
  );
}

/// Короткий доступ: `context.appColors.expense`.
extension AppColorsContext on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
