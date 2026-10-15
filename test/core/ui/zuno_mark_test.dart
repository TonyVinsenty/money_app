import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/zuno_mark.dart';

void main() {
  testWidgets('знак 48 dp по умолчанию и не озвучивается', (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: ZunoMark()),
      ),
    );
    expect(tester.getSize(find.byType(ZunoMark)), const Size.square(48));
    expect(
      find.descendant(
        of: find.byType(ZunoMark),
        matching: find.byType(ExcludeSemantics),
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  test('доли как у иконки варианта 1: по часовой от верха, с зазорами', () {
    const segments = ZunoMarkPainter.segments;
    expect(segments, hasLength(3));
    expect(segments.first.$1, 0);
    for (var i = 1; i < segments.length; i++) {
      // Зазор между долями — 3 % окружности.
      expect(segments[i].$1 - segments[i - 1].$2, closeTo(0.03, 1e-9));
    }
    expect(segments.map((s) => s.$3), const [
      Color(0xFF2F6FD6),
      Color(0xFFE9823A),
      Color(0xFF7B57C9),
    ]);
  });
}
