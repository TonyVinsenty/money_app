import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app_shell.dart';

const _labels = ['Главная', 'История', 'Аналитика', 'Баланс', 'Настройки'];

Future<void> _pump(WidgetTester tester, double width, double scale) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: AppShell(
        tabs: [
          for (final label in _labels)
            AppTab(
              label: label,
              icon: Icons.circle_outlined,
              selectedIcon: Icons.circle,
              builder: (_) => const SizedBox(),
            ),
        ],
      ),
    ),
  );
  await tester.pump();
}

void main() {
  for (final entry in [(320.0, 1.3), (320.0, 2.0), (375.0, 1.3)]) {
    testWidgets('подписи вкладок в одну строку: ${entry.$1} dp, '
        'шрифт ${entry.$2}', (tester) async {
      await _pump(tester, entry.$1, entry.$2);
      expect(tester.takeException(), isNull);
      final tabWidth = entry.$1 / _labels.length;
      // Высота одной строки: у подписи два слоя строки не бывает.
      double? lineHeight;
      for (final label in _labels) {
        final finder = find.text(label);
        expect(finder, findsOneWidget);
        final text = tester.widget<Text>(finder);
        expect(text.style?.fontSize, isNotNull);
        final rect = tester.getRect(finder);
        expect(rect.width, lessThanOrEqualTo(tabWidth));
        lineHeight ??= rect.height;
        // Одинаковая высота у всех подписей: ни одна не перенеслась.
        expect(rect.height, closeTo(lineHeight, 0.5));
        final render = tester.renderObject<RenderParagraph>(finder);
        // Одна строка: высота меньше двух размеров шрифта с запасом на интерлиньяж.
        expect(render.size.height, lessThan(text.style!.fontSize! * 2));
      }
    });
  }
}
