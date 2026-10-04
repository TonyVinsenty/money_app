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
}
