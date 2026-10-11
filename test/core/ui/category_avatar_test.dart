import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/category_avatar.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final entry in {
    'светлая': AppColors.light,
    'тёмная': AppColors.dark,
  }.entries) {
    test(
      'значок на цвете палитры, ${entry.key} тема: контраст не ниже 3:1',
      () {
        final fills = [...entry.value.chartPalette, entry.value.chartOther];
        for (final fill in fills) {
          final glyph = categoryAvatarForeground(fill);
          expect(
            _contrast(glyph, fill),
            greaterThanOrEqualTo(3),
            reason: 'заливка $fill',
          );
        }
      },
    );
  }

  testWidgets('заливка задана: кружок этого цвета, без неё - нейтральный', (
    tester,
  ) async {
    const fill = Color(0xFF1565C0);
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            CategoryAvatar('icon', color: fill),
            CategoryAvatar('icon'),
          ],
        ),
      ),
    );
    final colors = tester
        .widgetList<Container>(find.byType(Container))
        .map((c) => (c.decoration as BoxDecoration?)?.color)
        .toList();
    expect(colors.first, fill);
    expect(colors.last, isNot(fill));
  });
}
