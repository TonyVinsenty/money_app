import 'package:flutter/material.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';

/// Светлая и тёмная темы приложения (Material 3).
abstract final class AppTheme {
  // Спокойный сине-серый: не красный и не зелёный, чтобы не путаться
  // с цветами «расход»/«доход». Вариант `neutral` убирает из фонов
  // голубой оттенок: остаются почти серые поверхности.
  static const Color _seed = Color(0xFF546E7A);

  static ThemeData light() => _build(Brightness.light, AppColors.light);

  static ThemeData dark() => _build(Brightness.dark, AppColors.dark);

  static ThemeData _build(Brightness brightness, AppColors colors) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seed,
        brightness: brightness,
        dynamicSchemeVariant: DynamicSchemeVariant.neutral,
      ),
    );
    return base.copyWith(
      textTheme: _textTheme(base.textTheme),
      // Карточки отделяются от фона тоном, а не тенью (тень в тёмной теме
      // почти не видна).
      cardTheme: const CardThemeData(elevation: 0),
      extensions: <ThemeExtension<dynamic>>[colors],
    );
  }

  /// Иерархия текста: суммы — жирнее и крупнее подписей; цифры сумм
  /// одинаковой ширины, чтобы столбики сумм не «прыгали».
  static TextTheme _textTheme(TextTheme text) {
    const tabular = <FontFeature>[FontFeature.tabularFigures()];
    return text.copyWith(
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w500),
      titleMedium: text.titleMedium?.copyWith(fontFeatures: tabular),
      headlineSmall: text.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        fontFeatures: tabular,
      ),
      displaySmall: text.displaySmall?.copyWith(
        fontWeight: FontWeight.w600,
        fontFeatures: tabular,
      ),
      displayMedium: text.displayMedium?.copyWith(
        fontWeight: FontWeight.w600,
        fontFeatures: tabular,
      ),
    );
  }
}
