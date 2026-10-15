import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/app_segmented_button.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';

import '../../support/roboto_font.dart';

const _labels = ['Все', 'Расходы', 'Доходы'];

void main() {
  // Настоящий Roboto: тестовый шрифт рисует буквы квадратами.
  setUpAll(loadRoboto);

  Future<void> pumpAt(
    WidgetTester tester, {
    required double width,
    required double scale,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: AppSegmentedButton<int>(
              segments: [
                for (var i = 0; i < _labels.length; i++)
                  ButtonSegment(value: i, label: Text(_labels[i])),
              ],
              selected: const {0},
              onSelectionChanged: (_) {},
            ),
          ),
        ),
      ),
    );
  }

  Axis axisOf(WidgetTester tester) => tester
      .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
      .direction;

  void expectNoBrokenWords(WidgetTester tester) {
    for (final label in _labels) {
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(
          of: find.byType(SegmentedButton<int>),
          matching: find.text(label),
        ),
      );
      final lines = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: label.length),
      );
      // Слово одно, значит строка одна: разрыв дал бы две и больше.
      expect(lines.length, 1, reason: '$label разорвано');
    }
  }

  testWidgets('320 dp и 200 %: слова целы, переполнения нет', (tester) async {
    await pumpAt(tester, width: 320, scale: 2);
    expect(tester.takeException(), isNull);
    expectNoBrokenWords(tester);
  });

  testWidgets('320 dp и 130 %: слова целы', (tester) async {
    await pumpAt(tester, width: 320, scale: 1.3);
    expect(tester.takeException(), isNull);
    expectNoBrokenWords(tester);
  });

  testWidgets('412 dp и 100 %: горизонтально, поля прежние', (tester) async {
    await pumpAt(tester, width: 412, scale: 1);
    expect(axisOf(tester), Axis.horizontal);
    expect(
      tester
          .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
          .style,
      isNull,
    );
    expectNoBrokenWords(tester);
  });

  testWidgets('320 dp и 200 %: сегменты столбиком', (tester) async {
    await pumpAt(tester, width: 320, scale: 2);
    expect(axisOf(tester), Axis.vertical);
  });
}
