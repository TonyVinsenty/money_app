import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/donut_chart.dart';

const _size = Size(200, 200);

/// Точка на средней линии кольца под углом [turns] оборотов от «12 часов».
Offset _at(double turns, {double radius = 82}) {
  final a = turns * 2 * math.pi;
  return Offset(100 + radius * math.sin(a), 100 - radius * math.cos(a));
}

Widget _host(Widget child, {Size box = const Size(200, 300)}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: box.width,
          height: box.height,
          // Align ослабляет жёсткие ограничения SizedBox до «не больше».
          child: Align(child: child),
        ),
      ),
    ),
  );
}

List<DonutSegment> _segments(int n) => [
  for (var i = 0; i < n; i++)
    DonutSegment(weight: i + 1, color: Colors.primaries[i]),
];

void main() {
  group('sectorIndexAt', () {
    test('точка попадает в каждый из трёх секторов', () {
      const w = [1, 1, 2];
      expect(sectorIndexAt(_at(0.1), _size, w), 0);
      expect(sectorIndexAt(_at(0.4), _size, w), 1);
      expect(sectorIndexAt(_at(0.8), _size, w), 2);
    });

    test('граница: точка ровно на границе принадлежит следующему сектору', () {
      const w = [1, 1, 1, 1];
      // Ровно «3 часа» = граница секторов 0 и 1.
      expect(sectorIndexAt(const Offset(182, 100), _size, w), 1);
      // Чуть раньше границы это ещё сектор 0.
      expect(sectorIndexAt(_at(0.2499), _size, w), 0);
      // Ровно «12 часов» = начало сектора 0.
      expect(sectorIndexAt(const Offset(100, 18), _size, w), 0);
    });

    test('дырка и точка за краем дают null', () {
      const w = [1, 1];
      expect(sectorIndexAt(const Offset(100, 100), _size, w), isNull);
      expect(sectorIndexAt(_at(0.3, radius: 60), _size, w), isNull);
      expect(sectorIndexAt(_at(0.3, radius: 99), _size, w), isNull);
      expect(sectorIndexAt(const Offset(-10, -10), _size, w), isNull);
    });

    test('один сектор занимает весь круг', () {
      for (final t in [0.0, 0.25, 0.5, 0.75, 0.999]) {
        expect(sectorIndexAt(_at(t), _size, const [5]), 0);
      }
    });

    test('нулевые веса пропускаются', () {
      const w = [0, 1, 0, 1, 0];
      expect(sectorIndexAt(_at(0.1), _size, w), 1);
      expect(sectorIndexAt(_at(0.9), _size, w), 3);
    });

    test('пустой список и все нули дают null', () {
      expect(sectorIndexAt(_at(0.1), _size, const []), isNull);
      expect(sectorIndexAt(_at(0.1), _size, const [0, 0]), isNull);
    });
  });

  group('DonutChart', () {
    for (final n in [0, 1, 9]) {
      testWidgets('рисуется без ошибок для $n сегментов', (tester) async {
        await tester.pumpWidget(
          _host(DonutChart(segments: _segments(n), semanticsLabel: 'Расходы')),
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(DonutChart), findsOneWidget);
      });
    }

    testWidgets('рисуется с подсветкой и нулевым весом', (tester) async {
      await tester.pumpWidget(
        _host(
          const DonutChart(
            segments: [
              DonutSegment(weight: 0, color: Colors.red),
              DonutSegment(weight: 3, color: Colors.green),
              DonutSegment(weight: 1, color: Colors.blue),
            ],
            highlightedIndex: 1,
            semanticsLabel: 'Расходы',
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('центр показывается', (tester) async {
      await tester.pumpWidget(
        _host(
          DonutChart(
            segments: _segments(3),
            semanticsLabel: 'Расходы',
            center: const Text('Итого'),
          ),
        ),
      );
      expect(find.text('Итого'), findsOneWidget);
    });

    testWidgets('у скринридера ровно одна подпись, центр не добавляет узлов', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _host(
          DonutChart(
            segments: _segments(3),
            semanticsLabel: 'Расходы по категориям',
            center: const Text('Итого'),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Расходы по категориям'), findsOneWidget);
      expect(find.bySemanticsLabel('Итого'), findsNothing);
      handle.dispose();
    });

    testWidgets('размер квадратный по ширине родителя', (tester) async {
      await tester.pumpWidget(
        _host(DonutChart(segments: _segments(2), semanticsLabel: 'x')),
      );
      expect(tester.getSize(find.byType(DonutChart)), const Size(200, 200));
    });
  });

  group('касания', () {
    // Секторы: 0 и 1 по четверти круга, 2 нулевой, 3 половина круга.
    const segs = [
      DonutSegment(weight: 1, color: Colors.red),
      DonutSegment(weight: 1, color: Colors.green),
      DonutSegment(weight: 0, color: Colors.blue),
      DonutSegment(weight: 2, color: Colors.orange),
    ];
    final log = <String>[];
    int? shown;

    Widget chart({bool callbacks = true, bool scroll = false}) {
      Widget c = StatefulBuilder(
        builder: (context, setState) => DonutChart(
          segments: segs,
          semanticsLabel: 'x',
          highlightedIndex: shown,
          onHighlight: callbacks
              ? (i) {
                  log.add('h$i');
                  setState(() => shown = i);
                }
              : null,
          onSelect: callbacks ? (i) => log.add('s$i') : null,
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

    Offset global(WidgetTester tester, Offset local) =>
        tester.getTopLeft(find.byType(DonutChart)) + local;

    List<String> selects() => log.where((e) => e.startsWith('s')).toList();

    setUp(() {
      log.clear();
      shown = null;
    });

    testWidgets('короткое нажатие выбирает сектор', (tester) async {
      await tester.pumpWidget(chart());
      await tester.tapAt(global(tester, _at(0.1)));
      await tester.pump();
      expect(log, ['h0', 's0', 'hnull']);
    });

    testWidgets('долгое нажатие с переездом выбирает сектор отпускания', (
      tester,
    ) async {
      await tester.pumpWidget(chart());
      final g = await tester.startGesture(global(tester, _at(0.1)));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await g.moveTo(global(tester, _at(0.35)));
      await tester.pump();
      await g.moveTo(global(tester, _at(0.8)));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(log, containsAllInOrder(['h0', 'h1', 'h3', 's3', 'hnull']));
      expect(selects(), ['s3']);
      expect(shown, isNull);
    });

    testWidgets('отпускание в дырке и за краем не выбирает', (tester) async {
      await tester.pumpWidget(chart());
      for (final p in [const Offset(100, 100), const Offset(199, 1)]) {
        log.clear();
        final g = await tester.startGesture(global(tester, _at(0.1)));
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await g.moveTo(global(tester, p));
        await tester.pump();
        await g.up();
        await tester.pump();
        expect(selects(), isEmpty);
        expect(shown, isNull);
      }
    });

    testWidgets('нажатие в дырке ничего не выбирает', (tester) async {
      await tester.pumpWidget(chart());
      await tester.tapAt(global(tester, const Offset(100, 100)));
      await tester.pump();
      expect(selects(), isEmpty);
      expect(shown, isNull);
    });

    testWidgets('вертикальная прокрутка прокручивает и ничего не выбирает', (
      tester,
    ) async {
      await tester.pumpWidget(chart(scroll: true));
      final g = await tester.startGesture(global(tester, _at(0.1)));
      await tester.pump(const Duration(milliseconds: 150));
      expect(shown, 0);
      await g.moveBy(const Offset(0, -80));
      await tester.pump();
      await g.moveBy(const Offset(0, -80));
      await tester.pump();
      await g.up();
      await tester.pump();
      expect(shown, isNull);
      expect(selects(), isEmpty);
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scrollable.position.pixels, greaterThan(0));
    });

    testWidgets('без колбэков касания не обрабатываются', (tester) async {
      await tester.pumpWidget(chart(callbacks: false));
      await tester.tapAt(global(tester, _at(0.1)));
      await tester.pump();
      expect(log, isEmpty);
      expect(
        tester.widget<GestureDetector>(find.byType(GestureDetector)).onTapUp,
        isNull,
      );
    });
  });
}
