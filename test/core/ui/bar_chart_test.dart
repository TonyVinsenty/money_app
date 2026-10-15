import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/bar_chart.dart';
import 'package:money_app/core/ui/font_scale.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';

import '../../support/bar_taps.dart';
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

  group('шкала слева', () {
    test('три значения: 0, середина = половина верха, верх', () {
      expect(barScaleValues([100, 340, 20]), [0, 250, 500]);
      expect(barScaleValues([100], 600), [0, 500, 1000]);
    });

    test('y подписей: низ, середина, верх области столбиков', () {
      final v = barScaleValues([500]);
      expect(barScaleY(_size, [500], v[0]), closeTo(116, 1e-9));
      expect(barScaleY(_size, [500], v[1]), closeTo(66, 1e-9));
      expect(barScaleY(_size, [500], v[2]), closeTo(16, 1e-9));
    });

    test('отступ слева сдвигает столбики и сужает слоты', () {
      final r = barRects(_size, [500, 500], null, 0, 100);
      expect(r.first.left, greaterThanOrEqualTo(100));
      expect(r.last.right, lessThanOrEqualTo(300));
      expect(r[1].left - r[0].left, closeTo(100, 1e-9));
      expect(barIndexAt(const Offset(50, 50), _size, [1, 2], 100), 0);
      expect(barIndexAt(const Offset(250, 50), _size, [1, 2], 100), 1);
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

    test('полоса подписей оси: столбики кончаются выше, высота меньше', () {
      final r = barRects(_size, [500], null, barChartAxisHeight).single;
      expect(r.bottom, closeTo(100, 1e-9));
      expect(r.top, closeTo(16, 1e-9));
      expect(r.height, closeTo(84, 1e-9));
    });
  });

  group('подписи оси: геометрия', () {
    test('среднее учитывает полосу подписей', () {
      expect(
        barAverageY(_size, [500], 250, barChartAxisHeight),
        closeTo(58, 1e-9),
      );
    });

    test('подпись по центру слота', () {
      // 4 слота по 75 dp; подпись 20 dp в слоте 1 (центр 112,5).
      expect(barAxisLabelLeft(1, 4, 300, 20), closeTo(102.5, 1e-9));
    });

    test('крайние подписи сдвигаются внутрь', () {
      expect(barAxisLabelLeft(0, 31, 300, 30), 0);
      expect(barAxisLabelLeft(30, 31, 300, 30), closeTo(270, 1e-9));
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

    test('приглушённые заметно бледнее (не выше 0.5)', () {
      expect(barColor(const Color(0xFFC62828), 0, 1).a, lessThanOrEqualTo(0.5));
    });
  });

  group('масштаб подписей', () {
    const style = TextStyle(fontSize: 11);
    const labels = ['0', '2 500 ₽', '5 000 ₽'];
    double inset(double k) => barChartLeftInset(
      labels,
      style,
      TextScaler.linear(k).clamp(maxScaleFactor: chartLabelMaxScale),
    );

    test('при 100 % отступ как раньше: ширина подписи и 6 dp', () {
      final p = TextPainter(
        text: const TextSpan(text: '5 000 ₽', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(inset(1), closeTo(p.width + 6, 1e-9));
      expect(
        barChartAxisHeightFor(const TextScaler.linear(1)),
        barChartAxisHeight,
      );
    });

    test('при 130 % подписи и полоса оси крупнее', () {
      expect(inset(1.3), greaterThan(inset(1) * 1.2));
      expect(
        barChartAxisHeightFor(const TextScaler.linear(1.3)),
        closeTo(barChartAxisHeight * 1.3, 1e-9),
      );
    });

    test('при 200 % как при 130 %', () {
      expect(inset(2), closeTo(inset(1.3), 1e-9));
      final c = const TextScaler.linear(2).clamp(maxScaleFactor: 1.3);
      expect(barChartAxisHeightFor(c), closeTo(barChartAxisHeight * 1.3, 1e-9));
    });

    test('подписи шкалы не налезают на столбики: отступ не меньше ширины', () {
      const scaler = TextScaler.linear(1.3);
      final p = TextPainter(
        text: const TextSpan(text: '5 000 ₽', style: style),
        textScaler: scaler,
        textDirection: TextDirection.ltr,
      )..layout();
      final left = barRects(
        const Size(360, 160),
        [100, 200],
        null,
        0,
        inset(1.3),
      ).first.left;
      expect(left, greaterThanOrEqualTo(p.width + 6));
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
            semanticsLabel: 'x',
            highlightedIndex: 3,
          ),
        ),
      );
      expect(t.takeException(), isNull);
      expect(t.getSize(find.byType(BarChart)).width, 360);
    });

    testWidgets('подписи оси: 360 dp, 200 %, без переполнения и семантики', (
      t,
    ) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SizedBox(
              width: 360,
              child: BarChart(
                weights: List.generate(31, (i) => i * 100),
                axisLabels: const {0: '1', 9: '10', 19: '20', 30: '31'},
                color: Colors.red,
                topLabel: '5 000 ₽',
                semanticsLabel: 'график',
              ),
            ),
          ),
        ),
      );
      expect(t.takeException(), isNull);
      expect(t.getSize(find.byType(BarChart)).height, 160);
      expect(find.bySemanticsLabel('10'), findsNothing);
      expect(find.bySemanticsLabel('график'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('подписи оси: больше столбиков, чем индексов - без падения', (
      t,
    ) async {
      await t.pumpWidget(
        _host(
          const BarChart(
            weights: [1, 2],
            axisLabels: {0: 'a', 1: 'b', 5: 'x', -1: 'y'},
            color: Colors.red,
            topLabel: '2',
            semanticsLabel: 'x',
          ),
        ),
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('пустые и нулевые веса не падают', (t) async {
      await t.pumpWidget(
        _host(
          const BarChart(
            weights: [],
            color: Colors.red,
            topLabel: '',
            semanticsLabel: 'x',
          ),
        ),
      );
      await t.pumpWidget(
        _host(
          const BarChart(
            weights: [0, 0],
            color: Colors.red,
            topLabel: '0',
            semanticsLabel: 'x',
          ),
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

      const base = BarChart(
        weights: [1, 2],
        color: Colors.red,
        topLabel: 'a',
        semanticsLabel: 'x',
      );
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
            semanticsLabel: 'x',
            highlightedIndex: 0,
          ),
        ),
        isTrue,
      );
      expect(
        await changed(
          const BarChart(
            weights: [1, 3],
            color: Colors.red,
            topLabel: 'a',
            semanticsLabel: 'x',
          ),
        ),
        isTrue,
      );
      expect(
        await changed(
          const BarChart(
            weights: [1, 2],
            color: Colors.red,
            topLabel: 'a',
            semanticsLabel: 'x',
            average: 1,
          ),
        ),
        isTrue,
      );
      expect(
        await changed(
          const BarChart(
            weights: [1, 2],
            axisLabels: {0: 'Пн'},
            color: Colors.red,
            topLabel: 'a',
            semanticsLabel: 'x',
          ),
        ),
        isTrue,
      );
      expect(
        await changed(
          const BarChart(
            weights: [1, 2],
            color: Colors.red,
            topLabel: 'b',
            semanticsLabel: 'x',
          ),
        ),
        isTrue,
      );
    });
  });

  group('касания', () {
    // 4 слота по 50 dp в ширину 200; высота 100.
    const hold = Duration(milliseconds: 250);
    final log = <int?>[];
    int? shown;

    Widget chart({bool scroll = false, bool callbacks = true}) {
      Widget c = StatefulBuilder(
        builder: (context, setState) => BarChart(
          weights: const [1, 2, 0, 4],
          color: Colors.red,
          topLabel: '4',
          semanticsLabel: 'Расходы по дням',
          height: 100,
          highlightedIndex: shown,
          onHighlight: callbacks
              ? (i) {
                  log.add(i);
                  setState(() => shown = i);
                }
              : null,
        ),
      );
      if (scroll) {
        c = SingleChildScrollView(
          child: Column(children: [c, const SizedBox(height: 1000)]),
        );
      }
      return MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(width: 200, child: c),
          ),
        ),
      );
    }

    Offset at(WidgetTester t, int slot) =>
        t.getTopLeft(find.byType(BarChart)) + Offset(slot * 50.0 + 25, 60);

    setUp(() {
      log.clear();
      shown = null;
    });

    testWidgets('касание подсвечивает, отпускание снимает', (t) async {
      await t.pumpWidget(chart());
      final g = await t.startGesture(at(t, 1));
      await t.pump();
      expect(shown, 1);
      await g.up();
      await t.pump();
      expect(shown, isNull);
      expect(log, [1, null]);
    });

    testWidgets('ведение пальцем переезжает по столбикам', (t) async {
      await t.pumpWidget(chart());
      final g = await t.startGesture(at(t, 0));
      await g.moveTo(at(t, 2));
      await t.pump();
      expect(shown, 2);
      await g.moveTo(at(t, 3));
      await t.pump();
      expect(shown, 3);
      await g.up();
      await t.pump();
      expect(log, [0, 2, 3, null]);
    });

    testWidgets('отмена указателя снимает подсветку', (t) async {
      await t.pumpWidget(chart());
      final g = await t.startGesture(at(t, 1));
      await t.pump();
      await g.cancel();
      await t.pump();
      expect(shown, isNull);
    });

    testWidgets('быстрый свайп прокручивает родителя и снимает подсветку', (
      t,
    ) async {
      await t.pumpWidget(chart(scroll: true));
      final g = await t.startGesture(at(t, 1));
      await t.pump(const Duration(milliseconds: 100));
      expect(shown, 1);
      await g.moveBy(const Offset(0, -80));
      await t.pump();
      await g.moveBy(const Offset(0, -80));
      await t.pump();
      expect(shown, isNull);
      await g.up();
      await t.pump();
      expect(shown, isNull);
      final pixels = t
          .state<ScrollableState>(find.byType(Scrollable))
          .position
          .pixels;
      expect(pixels, greaterThan(0));
    });

    testWidgets('после удержания экран стоит, палец ведёт подсветку', (
      t,
    ) async {
      await t.pumpWidget(chart(scroll: true));
      final g = await t.startGesture(at(t, 0));
      await t.pump(hold);
      await g.moveTo(at(t, 3));
      await t.pump();
      expect(shown, 3);
      final position = t.state<ScrollableState>(find.byType(Scrollable));
      expect(position.position.pixels, 0);
      await g.up();
      await t.pumpAndSettle();
      expect(shown, isNull);
    });

    testWidgets('график убран во время жеста: слушатель прокрутки снят', (
      t,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final show = ValueNotifier(true);
      addTearDown(show.dispose);
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 200,
                child: SingleChildScrollView(
                  controller: controller,
                  child: Column(
                    children: [
                      ValueListenableBuilder(
                        valueListenable: show,
                        builder: (context, visible, _) => visible
                            ? BarChart(
                                weights: const [1, 2, 0, 4],
                                color: Colors.red,
                                topLabel: '4',
                                semanticsLabel: 'x',
                                height: 100,
                                onHighlight: log.add,
                              )
                            : const SizedBox(height: 100),
                      ),
                      const SizedBox(height: 1000),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      final g = await t.startGesture(const Offset(75, 60));
      await t.pump();
      expect(log, [1]);
      show.value = false;
      await t.pump();
      controller.jumpTo(50);
      await t.pump();
      expect(t.takeException(), isNull);
      expect(log, [1]);
      await g.up();
      await t.pump();
      expect(t.takeException(), isNull);
    });

    testWidgets('меньше столбиков при подсвеченном большом индексе', (t) async {
      Widget c(List<int> w, int? h) => _host(
        BarChart(
          weights: w,
          color: Colors.red,
          topLabel: 'x',
          semanticsLabel: 'x',
          highlightedIndex: h,
        ),
      );
      await t.pumpWidget(c(List.filled(31, 5), 25));
      await t.pumpWidget(c([5, 6], 25));
      expect(t.takeException(), isNull);
      expect(barColor(Colors.red, 0, 25).a, lessThan(1));
    });

    testWidgets('без onHighlight касания игнорируются', (t) async {
      await t.pumpWidget(chart(callbacks: false));
      await t.tapAt(at(t, 1));
      await t.pump();
      expect(log, isEmpty);
    });

    testWidgets('один семантический узел с подписью', (t) async {
      final handle = t.ensureSemantics();
      await t.pumpWidget(chart());
      expect(find.bySemanticsLabel('Расходы по дням'), findsOneWidget);
      expect(find.bySemanticsLabel('4'), findsNothing);
      handle.dispose();
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
        test('${entry.key} тема: ${c.key}, обычный и выбранный', () {
          expect(contrastRatio(c.value, surface), greaterThanOrEqualTo(3.0));
          // Выбранный столбик рисуется основным цветом. Приглушённые из
          // требования исключены: значение выбранного показано текстом.
          expect(
            contrastRatio(barColor(c.value, 1, 1), surface),
            greaterThanOrEqualTo(3.0),
          );
        });
      }
    }
  });

  group('рост столбиков', () {
    test('growBar: низ и ширина на месте, высота — доля', () {
      const bar = Rect.fromLTWH(10, 40, 8, 60);
      expect(growBar(bar, 0), const Rect.fromLTWH(10, 100, 8, 0));
      expect(growBar(bar, 0.5), const Rect.fromLTWH(10, 70, 8, 30));
      expect(growBar(bar, 1), bar);
      // За пределами 0..1 — как на краях.
      expect(growBar(bar, -1).height, 0);
      expect(growBar(bar, 2), bar);
    });

    double progressOf(WidgetTester t) =>
        (t.state(find.byType(BarChart)) as dynamic).progress as double;

    Widget chart(
      List<int> weights, {
      bool reduceMotion = false,
      int? highlighted,
      ValueChanged<int?>? onHighlight,
    }) => MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: BarChart(
                weights: weights,
                color: Colors.red,
                topLabel: '5 000 ₽',
                semanticsLabel: 'x',
                highlightedIndex: highlighted,
                onHighlight: onHighlight,
              ),
            ),
          ),
        ),
      ),
    );

    testWidgets('первый показ: от 0 до полной высоты за время кольца', (
      t,
    ) async {
      await t.pumpWidget(chart([100, 300, 200]));
      expect(progressOf(t), 0);
      await t.pump(const Duration(milliseconds: 300));
      expect(progressOf(t), inExclusiveRange(0, 1));
      await t.pumpAndSettle();
      expect(progressOf(t), 1);
    });

    testWidgets('«Уменьшить движение»: сразу целиком', (t) async {
      await t.pumpWidget(chart([100, 300, 200], reduceMotion: true));
      expect(progressOf(t), 1);
      expect(t.hasRunningAnimations, isFalse);
      await t.pumpWidget(chart([50, 60], reduceMotion: true));
      expect(progressOf(t), 1);
      expect(t.hasRunningAnimations, isFalse);
    });

    testWidgets('другие значения (период, категория) — растут заново', (
      t,
    ) async {
      await t.pumpWidget(chart([100, 300, 200]));
      await t.pumpAndSettle();
      await t.pumpWidget(chart([100, 300, 250]));
      expect(progressOf(t), 0);
      await t.pumpAndSettle();
      expect(progressOf(t), 1);
    });

    testWidgets('подсветка и те же значения рост не перезапускают', (t) async {
      await t.pumpWidget(chart([100, 300, 200]));
      await t.pumpAndSettle();
      await t.pumpWidget(chart([100, 300, 200], highlighted: 1));
      expect(progressOf(t), 1);
      expect(t.hasRunningAnimations, isFalse);
    });

    testWidgets('касание во время роста подсвечивает свой столбик', (t) async {
      final picked = <int?>[];
      await t.pumpWidget(chart([100, 300, 200], onHighlight: picked.add));
      await t.pump(const Duration(milliseconds: 100));
      expect(progressOf(t), inExclusiveRange(0, 1));

      final finder = find.byType(BarChart);
      // Верх графика: столбик ещё не дорос, но слот тот же.
      final gesture = await t.startGesture(
        barSlotPoint(t, finder, 2, 3, dy: 20),
      );
      expect(picked, [2]);
      await gesture.up();
      expect(picked, [2, null]);
      await t.pumpAndSettle();
    });
  });

  group('barFutureRects (И5, шаг 8.45)', () {
    test('с futureFrom до конца, на месте столбиков, во всю высоту', () {
      final weights = List<int>.filled(31, 100);
      final bars = barRects(_size, weights);
      final future = barFutureRects(_size, 31, 14);
      expect(future, hasLength(17));
      for (var i = 0; i < 17; i++) {
        final bar = bars[14 + i];
        expect(future[i].left, moreOrLessEquals(bar.left));
        expect(future[i].right, moreOrLessEquals(bar.right));
        expect(future[i].bottom, moreOrLessEquals(bar.bottom));
        expect(future[i].top, barChartLabelHeight);
      }
    });

    test('с отступом слева и полосой оси — как столбики', () {
      final bars = barRects(_size, [1, 2, 3], null, 16, 40);
      final future = barFutureRects(_size, 3, 1, 16, 40);
      expect(future, hasLength(2));
      expect(future.first.left, moreOrLessEquals(bars[1].left));
      expect(future.last.bottom, moreOrLessEquals(bars[2].bottom));
    });

    test('будущих нет или весов нет — пусто', () {
      expect(barFutureRects(_size, 30, 30), isEmpty);
      expect(barFutureRects(_size, 0, 0), isEmpty);
    });
  });

  group('barAverageLineEnd (шаг 8.55)', () {
    test('будущих нет — до правого края', () {
      expect(barAverageLineEnd(_size, 31, null), _size.width);
      expect(barAverageLineEnd(_size, 31, 31), _size.width);
      expect(barAverageLineEnd(_size, 0, 0), _size.width);
    });

    test('кончается на границе сегодняшнего и первого будущего столбика', () {
      // 30 слотов по 10 dp: будущие с 14-го — граница на 140.
      expect(barAverageLineEnd(_size, 30, 14), moreOrLessEquals(140));
      final future = barFutureRects(_size, 30, 14);
      expect(barAverageLineEnd(_size, 30, 14), lessThan(future.first.left));
    });

    test('с отступом слева под шкалу', () {
      // Слоты по (300 − 60) / 4 = 60 dp: граница после 2 слотов — 180.
      expect(barAverageLineEnd(_size, 4, 2, 60), moreOrLessEquals(180));
    });
  });
}
