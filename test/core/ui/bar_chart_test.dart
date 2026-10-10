import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/bar_chart.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';

import '../../support/contrast.dart';

// Область столбиков 100 dp плюс 16 dp под подпись.
const _size = Size(300, 116);

Widget _host(Widget chart, {double width = 360}) => MaterialApp(
  home: Scaffold(
    body: Center(
      child: SizedBox(width: width, child: chart),
    ),
  ),
);

void main() {
  group('barChartCeiling', () {
    test('круглый верх от максимума и среднего', () {
      expect(barChartCeiling([100, 340, 20]), 500);
      expect(barChartCeiling([100], 600), 1000);
      expect(barChartCeiling([]), 1);
      expect(barChartCeiling([0, 0]), 1);
    });
  });

  group('barRects', () {
    test('нет весов - пусто', () {
      expect(barRects(_size, []), isEmpty);
    });

    test('нулевые столбики - нулевой высоты на нижней линии', () {
      final r = barRects(_size, [0, 0, 0]);
      expect(r, hasLength(3));
      for (final x in r) {
        expect(x.height, 0);
        expect(x.bottom, 116);
      }
    });

    test('один столбик: по центру, 70 % ширины, максимум до верха шкалы', () {
      final r = barRects(_size, [500]).single;
      expect(r.width, closeTo(210, 1e-9));
      expect(r.center.dx, closeTo(150, 1e-9));
      expect(r.height, closeTo(100, 1e-9));
      expect(r.top, closeTo(16, 1e-9));
    });

    test('высота пропорциональна весу, малый вес не ниже 1 dp', () {
      final r = barRects(_size, [100, 250, 1]);
      expect(r[0].height, closeTo(40, 1e-9));
      expect(r[1].height, closeTo(100, 1e-9));
      expect(r[2].height, 1);
    });

    test('31 столбик на 300 dp: слоты равны, столбики не пересекаются', () {
      final r = barRects(_size, List.filled(31, 10));
      expect(r, hasLength(31));
      expect(r.first.left, greaterThanOrEqualTo(0));
      expect(r.last.right, lessThanOrEqualTo(300));
      for (var i = 1; i < r.length; i++) {
        expect(r[i].left, greaterThan(r[i - 1].right));
        expect(r[i].left - r[i - 1].left, closeTo(300 / 31, 1e-9));
      }
    });

    test('12 столбиков на 300 dp', () {
      final r = barRects(_size, List.filled(12, 10));
      expect(r, hasLength(12));
      expect(r.last.right, lessThanOrEqualTo(300));
      expect(r[1].left - r[0].left, closeTo(25, 1e-9));
    });

    test('среднее выше максимума поднимает шкалу', () {
      final r = barRects(_size, [100], 1000);
      expect(r.single.height, closeTo(10, 1e-9));
    });
  });

  group('barAverageY', () {
    test('на высоте среднего относительно верха шкалы', () {
      expect(barAverageY(_size, [500], 250), closeTo(66, 1e-9));
      expect(barAverageY(_size, [500], 500), closeTo(16, 1e-9));
      expect(barAverageY(_size, [500], 0), closeTo(116, 1e-9));
    });
  });

  group('barIndexAt', () {
    test('слот под точкой; в зазоре - ближайший по x', () {
      const w = [1, 2, 3, 4];
      expect(barIndexAt(const Offset(10, 50), _size, w), 0);
      expect(barIndexAt(const Offset(80, 50), _size, w), 1);
      // Слот 75 dp, граница столбиков 0 и 1 на x = 75.
      expect(barIndexAt(const Offset(74, 50), _size, w), 0);
      expect(barIndexAt(const Offset(76, 50), _size, w), 1);
      expect(barIndexAt(const Offset(300, 50), _size, w), 3);
    });

    test('нулевой столбик тоже выбирается, высота не важна', () {
      expect(barIndexAt(const Offset(10, 5), _size, [0, 5]), 0);
    });

    test('за пределами и без весов - null', () {
      expect(barIndexAt(const Offset(-1, 50), _size, [1]), isNull);
      expect(barIndexAt(const Offset(301, 50), _size, [1]), isNull);
      expect(barIndexAt(const Offset(10, 117), _size, [1]), isNull);
      expect(barIndexAt(const Offset(10, 50), _size, []), isNull);
    });
  });

  group('barColor', () {
    test('без подсветки и у подсвеченного как есть, остальные приглушены', () {
      const c = Color(0xFFC62828);
      expect(barColor(c, 0, null), c);
      expect(barColor(c, 1, 1), c);
      expect(barColor(c, 0, 1).a, lessThan(1));
    });
  });

  group('BarChart', () {
    testWidgets('рисуется без переполнения на 360 dp, 31 столбик', (t) async {
      await t.pumpWidget(
        _host(
          BarChart(
            weights: List.generate(31, (i) => i * 100),
            average: 1500,
            color: Colors.red,
            topLabel: '5 000 ₽',
            highlightedIndex: 3,
          ),
        ),
      );
      expect(t.takeException(), isNull);
      expect(t.getSize(find.byType(BarChart)).width, 360);
    });

    testWidgets('пустые и нулевые веса не падают', (t) async {
      await t.pumpWidget(
        _host(const BarChart(weights: [], color: Colors.red, topLabel: '')),
      );
      await t.pumpWidget(
        _host(
          const BarChart(weights: [0, 0], color: Colors.red, topLabel: '0'),
        ),
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('shouldRepaint: подсветка, веса, среднее, подпись', (t) async {
      Future<CustomPainter> painter(BarChart c) async {
        await t.pumpWidget(_host(c));
        final paint = t.widget<CustomPaint>(
          find.descendant(
            of: find.byType(BarChart),
            matching: find.byType(CustomPaint),
          ),
        );
        return paint.painter!;
      }

      const base = BarChart(weights: [1, 2], color: Colors.red, topLabel: 'a');
      final old = await painter(base);
      Future<bool> changed(BarChart c) async =>
          (await painter(c)).shouldRepaint(old);

      expect(await changed(base), isFalse);
      expect(
        await changed(
          const BarChart(
            weights: [1, 2],
            color: Colors.red,
            topLabel: 'a',
            highlightedIndex: 0,
          ),
        ),
        isTrue,
      );
      expect(
        await changed(
          const BarChart(weights: [1, 3], color: Colors.red, topLabel: 'a'),
        ),
        isTrue,
      );
      expect(
        await changed(
          const BarChart(
            weights: [1, 2],
            color: Colors.red,
            topLabel: 'a',
            average: 1,
          ),
        ),
        isTrue,
      );
      expect(
        await changed(
          const BarChart(weights: [1, 2], color: Colors.red, topLabel: 'b'),
        ),
        isTrue,
      );
    });
  });

  group('контраст столбиков с фоном не ниже 3:1', () {
    final themes = {
      'светлая': (AppTheme.light(), AppColors.light),
      'тёмная': (AppTheme.dark(), AppColors.dark),
    };
    for (final entry in themes.entries) {
      final (theme, colors) = entry.value;
      final surface = theme.colorScheme.surface;
      final bars = {'расход': colors.expense, 'доход': colors.income};
      for (final c in bars.entries) {
        test('${entry.key} тема: ${c.key}, обычный и приглушённый', () {
          expect(contrastRatio(c.value, surface), greaterThanOrEqualTo(3.0));
          expect(
            contrastRatio(barColor(c.value, 0, 1), surface),
            greaterThanOrEqualTo(3.0),
          );
        });
      }
    }
  });
}
