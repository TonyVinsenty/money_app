import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';

/// Контраст двух цветов по WCAG: (L1 + 0.05) / (L2 + 0.05), где L1 >= L2.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  test('светлая и тёмная темы имеют правильную яркость', () {
    expect(AppTheme.light().brightness, Brightness.light);
    expect(AppTheme.dark().brightness, Brightness.dark);
  });

  test('в обеих темах есть расширение AppColors со своим набором', () {
    expect(AppTheme.light().extension<AppColors>(), AppColors.light);
    expect(AppTheme.dark().extension<AppColors>(), AppColors.dark);
  });

  group('контраст с surface не ниже 4.5:1 (WCAG AA)', () {
    final themes = {
      'светлая': (AppTheme.light(), AppColors.light),
      'тёмная': (AppTheme.dark(), AppColors.dark),
    };
    for (final entry in themes.entries) {
      final (theme, colors) = entry.value;
      final surface = theme.colorScheme.surface;

      test('${entry.key} тема: расход', () {
        expect(
          contrastRatio(colors.expense, surface),
          greaterThanOrEqualTo(4.5),
        );
      });
      test('${entry.key} тема: доход', () {
        expect(
          contrastRatio(colors.income, surface),
          greaterThanOrEqualTo(4.5),
        );
      });
    }
  });

  test('copyWith заменяет только переданные поля', () {
    const base = AppColors.light;

    final changed = base.copyWith(income: Colors.blue);

    expect(changed.income, Colors.blue);
    expect(changed.expense, base.expense);
    expect(base.copyWith().expense, base.expense);
    expect(base.copyWith().income, base.income);
  });

  test('lerp при t=0 даёт исходные цвета, при t=1 — цвета второго набора', () {
    final atStart = AppColors.light.lerp(AppColors.dark, 0);
    final atEnd = AppColors.light.lerp(AppColors.dark, 1);

    expect(atStart.expense, AppColors.light.expense);
    expect(atStart.income, AppColors.light.income);
    expect(atEnd.expense, AppColors.dark.expense);
    expect(atEnd.income, AppColors.dark.income);
  });

  group('равенство', () {
    test('одинаковое содержимое: равны и hashCode совпадает', () {
      const a = AppColors(
        expense: Color(0xFF112233),
        income: Color(0xFF445566),
      );
      const b = AppColors(
        expense: Color(0xFF112233),
        income: Color(0xFF445566),
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('copyWith с другим значением не равен исходному', () {
      const base = AppColors.light;

      expect(base.copyWith(income: Colors.blue), isNot(base));
      expect(base.copyWith(expense: Colors.blue), isNot(base));
      expect(base.copyWith(), base);
    });

    test('lerp: при t=0 равен исходному, при t=1 равен второму', () {
      expect(AppColors.light.lerp(AppColors.dark, 0), AppColors.light);
      expect(AppColors.light.lerp(AppColors.dark, 1), AppColors.dark);
    });

    test('объект другого типа не равен', () {
      // Тип Object скрывает настоящий тип от анализатора: сравнение намеренное.
      final Object other = Colors.red;
      expect(AppColors.light == other, isFalse);
    });
  });

  test('lerp с не-AppColors возвращает исходный объект', () {
    expect(AppColors.light.lerp(null, 0.5), AppColors.light);
  });
}
