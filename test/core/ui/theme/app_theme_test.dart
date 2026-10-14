import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';

import '../../../support/contrast.dart';

void main() {
  final themes = {'светлая': AppTheme.light(), 'тёмная': AppTheme.dark()};

  group('нейтральная палитра', () {
    for (final entry in themes.entries) {
      test('${entry.key} тема: фон почти серый (каналы RGB почти равны)', () {
        // HSL-насыщенность для очень светлых цветов обманчива, поэтому
        // сравниваем разброс красного, зелёного и синего (0..255).
        final surface = entry.value.colorScheme.surface;
        final channels = [
          (surface.r * 255).round(),
          (surface.g * 255).round(),
          (surface.b * 255).round(),
        ];
        final spread =
            channels.reduce((a, b) => a > b ? a : b) -
            channels.reduce((a, b) => a < b ? a : b);
        expect(spread, lessThanOrEqualTo(4));
      });
    }
  });

  group('текст читается на поверхностях (WCAG AA, 4.5:1)', () {
    for (final entry in themes.entries) {
      final scheme = entry.value.colorScheme;
      final surfaces = {
        'surface': scheme.surface,
        'surfaceContainerHighest': scheme.surfaceContainerHighest,
      };
      for (final surface in surfaces.entries) {
        test('${entry.key} тема, ${surface.key}: onSurface', () {
          expect(
            contrastRatio(scheme.onSurface, surface.value),
            greaterThanOrEqualTo(4.5),
          );
        });
        test('${entry.key} тема, ${surface.key}: onSurfaceVariant', () {
          expect(
            contrastRatio(scheme.onSurfaceVariant, surface.value),
            greaterThanOrEqualTo(4.5),
          );
        });
      }
    }
  });

  group('акцентный цвет (синий)', () {
    for (final entry in themes.entries) {
      final scheme = entry.value.colorScheme;
      final brightness = scheme.brightness;

      test('${entry.key} тема: onPrimary на primary ≥ 4.5', () {
        expect(
          contrastRatio(scheme.onPrimary, scheme.primary),
          greaterThanOrEqualTo(4.5),
        );
      });
      test('${entry.key} тема: primary на surface ≥ 4.5', () {
        expect(
          contrastRatio(scheme.primary, scheme.surface),
          greaterThanOrEqualTo(4.5),
        );
      });
      test('${entry.key} тема: primary на surfaceContainerHighest ≥ 4.5', () {
        expect(
          contrastRatio(scheme.primary, scheme.surfaceContainerHighest),
          greaterThanOrEqualTo(4.5),
        );
      });
      test(
        '${entry.key} тема: фоны и текст как в прежней нейтральной схеме',
        () {
          final old = ColorScheme.fromSeed(
            seedColor: const Color(0xFF546E7A),
            brightness: brightness,
            dynamicSchemeVariant: DynamicSchemeVariant.neutral,
          );
          expect(scheme.surface, old.surface);
          expect(scheme.onSurface, old.onSurface);
          expect(scheme.surfaceContainerHighest, old.surfaceContainerHighest);
          expect(scheme.outline, old.outline);
        },
      );
    }
  });

  group('карточки без тени', () {
    for (final entry in themes.entries) {
      test('${entry.key} тема: cardTheme.elevation == 0', () {
        expect(entry.value.cardTheme.elevation, 0);
      });
    }
  });

  group('суммы выделены весом и выровнены по цифрам', () {
    for (final entry in themes.entries) {
      final text = entry.value.textTheme;

      test('${entry.key} тема: крупная сумма (headlineSmall) весом ≥ 600', () {
        expect(text.headlineSmall?.fontWeight, isNotNull);
        expect(
          text.headlineSmall!.fontWeight!.value,
          greaterThanOrEqualTo(600),
        );
      });

      test('${entry.key} тема: сумма ввода (displaySmall) весом ≥ 600', () {
        expect(text.displaySmall!.fontWeight!.value, greaterThanOrEqualTo(600));
      });

      test('${entry.key} тема: цифры сумм табличные', () {
        for (final style in [
          text.displaySmall,
          text.displayMedium,
          text.headlineSmall,
          text.titleMedium,
        ]) {
          expect(
            style!.fontFeatures,
            contains(const FontFeature.tabularFigures()),
          );
        }
      });

      test('${entry.key} тема: заголовок экрана (titleLarge) весом 500', () {
        expect(text.titleLarge!.fontWeight, FontWeight.w500);
      });
    }
  });

  group('поля ввода', () {
    for (final entry in themes.entries) {
      final input = entry.value.inputDecorationTheme;
      final scheme = entry.value.colorScheme;

      test('${entry.key} тема: рамка OutlineInputBorder, радиус 12', () {
        for (final border in [
          input.border,
          input.enabledBorder,
          input.focusedBorder,
          input.errorBorder,
          input.focusedErrorBorder,
        ]) {
          expect(border, isA<OutlineInputBorder>());
          expect(
            (border! as OutlineInputBorder).borderRadius,
            BorderRadius.circular(12),
          );
        }
      });

      test('${entry.key} тема: фокус — акцент, ошибка — error', () {
        expect(input.focusedBorder!.borderSide.color, scheme.primary);
        expect(input.errorBorder!.borderSide.color, scheme.error);
        expect(input.focusedErrorBorder!.borderSide.color, scheme.error);
      });
    }
  });

  group('скругления', () {
    for (final entry in themes.entries) {
      test('${entry.key} тема: карточка скруглена на 16', () {
        final shape = entry.value.cardTheme.shape as RoundedRectangleBorder;
        expect(shape.borderRadius, BorderRadius.circular(16));
      });
    }
  });

  group('по-айфонному (ADR 0013, п. 6)', () {
    for (final make in [AppTheme.light, AppTheme.dark]) {
      test('iOS: без «волны» нажатия', () {
        final theme = make(platform: TargetPlatform.iOS);
        expect(theme.platform, TargetPlatform.iOS);
        expect(theme.splashFactory, same(NoSplash.splashFactory));
      });

      test('Android: «волна» Material на месте', () {
        final theme = make(platform: TargetPlatform.android);
        expect(theme.splashFactory, isNot(same(NoSplash.splashFactory)));
        expect(
          theme.splashFactory,
          ThemeData(platform: TargetPlatform.android).splashFactory,
        );
      });
    }
  });

  group('сообщения и меню (8.1)', () {
    for (final entry in themes.entries) {
      test('${entry.key} тема: сообщение плавающее, радиус 12, зазор 8', () {
        final snack = entry.value.snackBarTheme;
        expect(snack.behavior, SnackBarBehavior.floating);
        expect(
          (snack.shape! as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(12),
        );
        expect(snack.insetPadding, const EdgeInsets.fromLTRB(16, 0, 16, 8));
      });

      test('${entry.key} тема: меню — радиус 12, фон surfaceContainerHigh', () {
        final theme = entry.value;
        final high = theme.colorScheme.surfaceContainerHigh;
        final popup = theme.popupMenuTheme;
        expect(
          (popup.shape! as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(12),
        );
        expect(popup.color, high);
        final style = theme.menuTheme.style!;
        expect(
          (style.shape!.resolve({})! as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(12),
        );
        expect(style.backgroundColor!.resolve({}), high);
      });
    }
  });
}
