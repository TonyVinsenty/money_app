import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/category_icon_view.dart';
import 'package:money_app/core/ui/category_icons.dart';

Widget _host(Widget child, {double textScale = 1.0}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('значок Material рисуется как Icon', (tester) async {
    await tester.pumpWidget(_host(const CategoryIconView('restaurant')));
    expect(find.byIcon(Icons.restaurant), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('символ рисуется как Text, а не Icon', (tester) async {
    await tester.pumpWidget(_host(const CategoryIconView('glyph:Ж')));
    expect(find.text('Ж'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('неизвестный ключ и null дают запасной значок', (tester) async {
    for (final key in <String?>['glyph:Ω', 'no_such', null]) {
      await tester.pumpWidget(_host(CategoryIconView(key)));
      expect(find.byIcon(fallbackCategoryIcon), findsOneWidget, reason: '$key');
      expect(find.byType(Text), findsNothing);
    }
  });

  testWidgets('значок скрыт от семантики', (tester) async {
    await tester.pumpWidget(_host(const CategoryIconView('glyph:Ж')));
    expect(find.bySemanticsLabel('Ж'), findsNothing);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('квадрат одного размера при шрифте $scale', (tester) async {
      Future<Size> sizeOf(String key) async {
        await tester.pumpWidget(
          _host(CategoryIconView(key, size: 24), textScale: scale),
        );
        return tester.getSize(find.byType(CategoryIconView));
      }

      expect(await sizeOf('restaurant'), const Size(24, 24));
      expect(await sizeOf('glyph:Ж'), const Size(24, 24));
      expect(await sizeOf('glyph:5'), const Size(24, 24));
    });
  }

  testWidgets('широкие Ш, Щ, W помещаются в 24 без переполнения', (
    tester,
  ) async {
    for (final key in ['glyph:Ш', 'glyph:Щ', 'glyph:W']) {
      await tester.pumpWidget(
        _host(CategoryIconView(key, size: 24), textScale: 2.0),
      );
      expect(tester.takeException(), isNull, reason: key);
      expect(tester.getSize(find.byType(CategoryIconView)), const Size(24, 24));
      final glyph = tester.getSize(find.byType(Text));
      expect(glyph.width, lessThanOrEqualTo(24.01), reason: key);
    }
  });
}
