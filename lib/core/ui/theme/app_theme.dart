import 'package:flutter/material.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';

/// Светлая и тёмная темы приложения (Material 3).
abstract final class AppTheme {
  // Спокойный сине-серый: не красный и не зелёный, чтобы не путаться
  // с цветами «расход»/«доход».
  static const Color _seed = Color(0xFF546E7A);

  static ThemeData light() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.light,
    ),
    extensions: const <ThemeExtension<dynamic>>[AppColors.light],
  );

  static ThemeData dark() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    ),
    extensions: const <ThemeExtension<dynamic>>[AppColors.dark],
  );
}
