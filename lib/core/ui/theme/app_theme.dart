import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';

/// Цвет только для выбранного состояния. Сравнивается по значению: тема,
/// собранная заново, остаётся равной прежней, и `AnimatedTheme` не запускает
/// лишний переход (иначе в тестах и при пересборке тема «анимируется»).
class _SelectedColor extends WidgetStateProperty<Color?> {
  _SelectedColor(this.color);

  final Color color;

  @override
  Color? resolve(Set<WidgetState> states) =>
      states.contains(WidgetState.selected) ? color : null;

  @override
  bool operator ==(Object other) =>
      other is _SelectedColor && other.color == color;

  @override
  int get hashCode => color.hashCode;
}

/// Светлая и тёмная темы приложения (Material 3).
abstract final class AppTheme {
  // Спокойный сине-серый: не красный и не зелёный, чтобы не путаться
  // с цветами «расход»/«доход». Вариант `neutral` убирает из фонов
  // голубой оттенок: остаются почти серые поверхности.
  static const Color _seed = Color(0xFF546E7A);

  // Акцент (кнопки, выбранные элементы): синий. Берём из его схемы только
  // группу primary; фоны и поверхности остаются нейтральными.
  static const Color _accentSeed = Color(0xFF2F6FD6);

  /// Нейтральная схема, у которой primary-группа заменена на синюю.
  static ColorScheme scheme(Brightness brightness) {
    final neutral = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.neutral,
    );
    final accent = ColorScheme.fromSeed(
      seedColor: _accentSeed,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    return neutral.copyWith(
      primary: accent.primary,
      onPrimary: accent.onPrimary,
      primaryContainer: accent.primaryContainer,
      onPrimaryContainer: accent.onPrimaryContainer,
      inversePrimary: accent.inversePrimary,
      surfaceTint: accent.primary,
    );
  }

  static const RoundedRectangleBorder _cardShape = RoundedRectangleBorder(
    borderRadius: AppRadius.borderL,
  );

  static const RoundedRectangleBorder _menuShape = RoundedRectangleBorder(
    borderRadius: AppRadius.borderM,
  );

  /// Нижнее сообщение: плавающая плашка со скруглением 12, поля 16 по бокам
  /// и зазор 8 снизу. Scaffold приложения ставит сообщение над всей нижней
  /// панелью (кнопки «Главной» и капсула вкладок лежат в её слоте), поэтому
  /// зазор 8 отсчитывается от верха этой панели; высоту капсулы считать не
  /// нужно. Цвета — по умолчанию.
  static const SnackBarThemeData snackBarTheme = SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    shape: _menuShape,
    insetPadding: EdgeInsets.fromLTRB(16, 0, 16, 8),
  );

  /// Строка состояния для темы: тёмные значки на светлой теме, светлые на
  /// тёмной. Android читает `statusBarIconBrightness`, iOS — `statusBarBrightness`
  /// (там он означает яркость самого фона, поэтому совпадает с темой).
  static SystemUiOverlayStyle overlayStyle(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isLight ? Brightness.dark : Brightness.light,
      statusBarBrightness: brightness,
    );
  }

  /// [platform] — для тестов; по умолчанию платформа устройства.
  static ThemeData light({TargetPlatform? platform}) =>
      _build(Brightness.light, AppColors.light, platform);

  static ThemeData dark({TargetPlatform? platform}) =>
      _build(Brightness.dark, AppColors.dark, platform);

  static ThemeData _build(
    Brightness brightness,
    AppColors colors,
    TargetPlatform? platform,
  ) {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme(brightness),
      platform: platform,
    );
    return base.copyWith(
      // iOS: без «волны» от пальца (ADR 0013, п. 6); подсветка нажатия
      // остаётся. Android — как в Material.
      splashFactory: base.platform == TargetPlatform.iOS
          ? NoSplash.splashFactory
          : base.splashFactory,
      textTheme: _textTheme(base.textTheme),
      // Карточки отделяются от фона тоном, а не тенью (тень в тёмной теме
      // почти не видна).
      cardTheme: const CardThemeData(elevation: 0, shape: _cardShape),
      inputDecorationTheme: _inputTheme(base.colorScheme),
      // Шапка не голубеет при прокрутке (без оттенка и подъёма), значки
      // строки состояния — по теме.
      appBarTheme: AppBarTheme(
        backgroundColor: base.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        systemOverlayStyle: overlayStyle(brightness),
      ),
      datePickerTheme: DatePickerThemeData(
        rangePickerHeaderBackgroundColor: base.colorScheme.surface,
      ),
      snackBarTheme: snackBarTheme,
      // Выбранный сегмент — акцентом, невыбранный — как обычный текст.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: _SelectedColor(base.colorScheme.primaryContainer),
          foregroundColor: _SelectedColor(base.colorScheme.onPrimaryContainer),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        shape: _menuShape,
        color: base.colorScheme.surfaceContainerHigh,
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          shape: const WidgetStatePropertyAll(_menuShape),
          backgroundColor: WidgetStatePropertyAll(
            base.colorScheme.surfaceContainerHigh,
          ),
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[colors],
    );
  }

  /// Все поля ввода и выпадающие списки — в рамке с радиусом 12;
  /// фокус — акцентный цвет, ошибка — цвет ошибки.
  static InputDecorationTheme _inputTheme(ColorScheme scheme) {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: AppRadius.borderM,
      borderSide: BorderSide(color: color, width: width),
    );
    return InputDecorationTheme(
      border: border(scheme.outline, 1),
      enabledBorder: border(scheme.outline, 1),
      disabledBorder: border(scheme.outlineVariant, 1),
      focusedBorder: border(scheme.primary, 2),
      errorBorder: border(scheme.error, 1),
      focusedErrorBorder: border(scheme.error, 2),
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
