import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/app_card.dart';

void main() {
  testWidgets('AppCard: рамка outlineVariant, радиус 16, поля 16', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: const Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: AppCard(child: SizedBox(width: 100, height: 50)),
          ),
        ),
      ),
    );

    final card = tester.widget<Card>(find.byType(Card));
    final scheme = Theme.of(tester.element(find.byType(AppCard))).colorScheme;
    final shape = card.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(16));
    expect(shape.side.color, scheme.outlineVariant);
    expect(card.margin, EdgeInsets.zero);
    // Размер = содержимое + поля 16 с каждой стороны.
    expect(tester.getSize(find.byType(Card)), const Size(132, 82));
  });

  testWidgets('AppCard: свои поля', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: AppCard(
              padding: EdgeInsets.all(8),
              child: SizedBox(width: 100, height: 50),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(Card)), const Size(116, 66));
  });
}
