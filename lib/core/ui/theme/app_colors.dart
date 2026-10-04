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
  });

  /// Цвета для светлой темы.
  static const AppColors light = AppColors(
    expense: Color(0xFFB3261E),
    income: Color(0xFF1B6E3A),
    expenseAction: Color(0xFFB3261E),
    onExpenseAction: Color(0xFFFFFFFF),
    incomeAction: Color(0xFF1B6E3A),
    onIncomeAction: Color(0xFFFFFFFF),
  );

  /// Цвета для тёмной темы (светлее, чтобы читались на тёмном фоне).
  static const AppColors dark = AppColors(
    expense: Color(0xFFFF8A80),
    income: Color(0xFF7BD88F),
    expenseAction: Color(0xFF8C1D18),
    onExpenseAction: Color(0xFFF9DEDC),
    incomeAction: Color(0xFF1A5233),
    onIncomeAction: Color(0xFFC8EED2),
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

  @override
  AppColors copyWith({
    Color? expense,
    Color? income,
    Color? expenseAction,
    Color? onExpenseAction,
    Color? incomeAction,
    Color? onIncomeAction,
  }) {
    return AppColors(
      expense: expense ?? this.expense,
      income: income ?? this.income,
      expenseAction: expenseAction ?? this.expenseAction,
      onExpenseAction: onExpenseAction ?? this.onExpenseAction,
      incomeAction: incomeAction ?? this.incomeAction,
      onIncomeAction: onIncomeAction ?? this.onIncomeAction,
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
        other.onIncomeAction == onIncomeAction;
  }

  @override
  int get hashCode => Object.hash(
    expense,
    income,
    expenseAction,
    onExpenseAction,
    incomeAction,
    onIncomeAction,
  );
}

/// Короткий доступ: `context.appColors.expense`.
extension AppColorsContext on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
