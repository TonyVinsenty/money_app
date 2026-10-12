import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/amount_switcher.dart';

Widget _app(String text, {bool reduceMotion = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(
      body: AmountSwitcher(switchKey: text, child: Text(text)),
    ),
  ),
);

double _opacityOf(WidgetTester tester, String text) {
  final fade = tester.widget<FadeTransition>(
    find
        .ancestor(of: find.text(text), matching: find.byType(FadeTransition))
        .first,
  );
  return fade.opacity.value;
}

void main() {
  testWidgets('первый показ — сразу целиком', (tester) async {
    await tester.pumpWidget(_app('100 ₽'));
    expect(_opacityOf(tester, '100 ₽'), 1);
  });

  testWidgets('смена: в середине видны оба, затем только новое', (
    tester,
  ) async {
    await tester.pumpWidget(_app('100 ₽'));
    await tester.pumpWidget(_app('250 ₽'));
    await tester.pump(amountSwitchDuration ~/ 2);

    expect(find.text('100 ₽'), findsOneWidget);
    expect(find.text('250 ₽'), findsOneWidget);
    final fadingOut = _opacityOf(tester, '100 ₽');
    final fadingIn = _opacityOf(tester, '250 ₽');
    expect(fadingOut, inExclusiveRange(0, 1));
    expect(fadingIn, inExclusiveRange(0, 1));

    await tester.pumpAndSettle();
    expect(find.text('100 ₽'), findsNothing);
    expect(_opacityOf(tester, '250 ₽'), 1);
  });

  testWidgets('тот же ключ — без перехода', (tester) async {
    await tester.pumpWidget(_app('100 ₽'));
    await tester.pumpWidget(_app('100 ₽'));
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('100 ₽'), findsOneWidget);
  });

  testWidgets('«Уменьшить движение»: новое сразу, прежнего нет', (
    tester,
  ) async {
    await tester.pumpWidget(_app('100 ₽', reduceMotion: true));
    await tester.pumpWidget(_app('250 ₽', reduceMotion: true));

    expect(find.text('100 ₽'), findsNothing);
    expect(find.text('250 ₽'), findsOneWidget);
    expect(_opacityOf(tester, '250 ₽'), 1);
    expect(tester.hasRunningAnimations, isFalse);
  });
}
