import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/card_header.dart';

Widget _app(Widget child, {double scale = 1}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(body: SizedBox(width: 360, child: child)),
  ),
);

void main() {
  testWidgets('titleMedium, вес 600, слева, это заголовок для скринридера', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const CardHeader('Расходы по дням')));

    final text = tester.widget<Text>(find.text('Расходы по дням'));
    final base = Theme.of(tester.element(find.text('Расходы по дням')))
        .textTheme
        .titleMedium!;
    expect(text.style?.fontSize, base.fontSize);
    expect(text.style?.fontWeight, FontWeight.w600);
    expect(text.textAlign, TextAlign.start);
    expect(tester.getTopLeft(find.text('Расходы по дням')).dx, 0);
    expect(
      tester.getSemantics(find.text('Расходы по дням')),
      matchesSemantics(label: 'Расходы по дням', isHeader: true),
    );
  });

  testWidgets('centered: заголовок по центру', (tester) async {
    await tester.pumpWidget(
      _app(const CardHeader('Расходы по дням', centered: true)),
    );
    final text = tester.widget<Text>(find.text('Расходы по дням'));
    expect(text.textAlign, TextAlign.center);
    expect(tester.getCenter(find.text('Расходы по дням')).dx, 180);
  });

  testWidgets('справа одно действие', (tester) async {
    await tester.pumpWidget(
      _app(
        CardHeader(
          'Сравнение',
          trailing: IconButton(icon: const Icon(Icons.info), onPressed: () {}),
        ),
      ),
    );
    expect(find.byIcon(Icons.info), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('шрифт 200 %: длинный заголовок переносится, без overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(const CardHeader('Частота и средний чек расходов'), scale: 2),
    );
    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.text('Частота и средний чек расходов'));
    final single = (TextPainter(
      text: const TextSpan(
        text: 'Ч',
        style: TextStyle(fontSize: 16 * 2, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout()).height;
    expect(size.height, greaterThan(single * 1.5));
    expect(size.width, lessThanOrEqualTo(360));
  });
}
