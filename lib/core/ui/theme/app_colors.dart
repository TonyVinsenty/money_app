import 'package:flutter/material.dart';

/// Семантические цвета приложения: «расход» (красная гамма) и «доход» (зелёная).
///
/// Цвет не должен быть единственным носителем смысла: при показе суммы всегда
/// добавляйте знак («−»/«+») или иконку. Так сумму поймёт и человек, который
/// не различает красный и зелёный. Сами знак и иконки появятся в шаге с
/// виджетами суммы.
///
/// Оттенки подобраны так, чтобы контраст с фоном `ColorScheme.surface`
/// своей темы был не ниже 4.5:1 (WCAG AA для текста); это проверяет тест.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({required this.expense, required this.income});

  /// Цвета для светлой темы.
  static const AppColors light = AppColors(
    expense: Color(0xFFB3261E),
    income: Color(0xFF1B6E3A),
  );

  /// Цвета для тёмной темы (светлее, чтобы читались на тёмном фоне).
  static const AppColors dark = AppColors(
    expense: Color(0xFFFF8A80),
    income: Color(0xFF7BD88F),
  );

  final Color expense;
  final Color income;

  @override
  AppColors copyWith({Color? expense, Color? income}) {
    return AppColors(
      expense: expense ?? this.expense,
      income: income ?? this.income,
    );
  }

  @override
  AppColors lerp(covariant ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      expense: Color.lerp(expense, other.expense, t)!,
      income: Color.lerp(income, other.income, t)!,
    );
  }

  @override
  bool operator ==(Object other) {
    return other.runtimeType == runtimeType &&
        other is AppColors &&
        other.expense == expense &&
        other.income == income;
  }

  @override
  int get hashCode => Object.hash(expense, income);
}

/// Короткий доступ: `context.appColors.expense`.
extension AppColorsContext on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
