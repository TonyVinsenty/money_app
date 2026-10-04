import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/period_switcher.dart';

Widget _app({
  VoidCallback? onPrevious,
  VoidCallback? onNext,
  String label = 'Октябрь 2026',
  double textScale = 1,
  double width = 360,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 640),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: PeriodSwitcher(
              label: label,
              onPrevious: onPrevious,
              onNext: onNext,
              previousTooltip: 'Предыдущий месяц',
              nextTooltip: 'Следующий месяц',
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('taps call callbacks', (tester) async {
    var prev = 0;
    var next = 0;
    await tester.pumpWidget(
      _app(onPrevious: () => prev++, onNext: () => next++),
    );
    await tester.tap(find.byKey(PeriodSwitcher.previousKey));
    await tester.tap(find.byKey(PeriodSwitcher.nextKey));
    await tester.tap(find.byKey(PeriodSwitcher.nextKey));
    expect(prev, 1);
    expect(next, 2);
  });

  testWidgets('unavailable arrow is disabled and silent', (tester) async {
    var prev = 0;
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(onPrevious: () => prev++));
    final next = tester.widget<IconButton>(find.byKey(PeriodSwitcher.nextKey));
    expect(next.onPressed, isNull);
    await tester.tap(find.byKey(PeriodSwitcher.nextKey));
    expect(prev, 0);
    final node = tester.getSemantics(find.byKey(PeriodSwitcher.nextKey));
    expect(node.flagsCollection.isEnabled.name, 'isFalse');
    handle.dispose();
  });

  testWidgets('both unavailable: no arrows, label stays centered', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    expect(find.byType(IconButton), findsNothing);
    expect(find.byIcon(Icons.chevron_left), findsNothing);
    final center = tester.getCenter(find.text('Октябрь 2026'));
    expect(center.dx, closeTo(tester.getCenter(find.byType(Scaffold)).dx, 0.5));
  });

  testWidgets('label does not move when arrows hide', (tester) async {
    await tester.pumpWidget(_app(onPrevious: () {}, onNext: () {}));
    final before = tester.getCenter(find.text('Октябрь 2026'));
    await tester.pumpWidget(_app());
    expect(tester.getCenter(find.text('Октябрь 2026')), before);
  });

  testWidgets('arrows meet tap target guideline', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(onPrevious: () {}, onNext: () {}));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    expect(
      tester.getSize(find.byKey(PeriodSwitcher.previousKey)),
      const Size(48, 48),
    );
    handle.dispose();
  });

  testWidgets('200% font on 320 dp: no overflow, single line', (tester) async {
    await tester.pumpWidget(
      _app(
        onPrevious: () {},
        onNext: () {},
        label: 'Сентябрь 2026',
        textScale: 2,
        width: 320,
      ),
    );
    expect(tester.takeException(), isNull);
    final box = tester.getSize(find.text('Сентябрь 2026'));
    expect(box.height, lessThan(60));
  });

  testWidgets('label is a live region', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(onPrevious: () {}, onNext: () {}));
    expect(
      tester.getSemantics(find.text('Октябрь 2026')),
      matchesSemantics(label: 'Октябрь 2026', isLiveRegion: true),
    );
    handle.dispose();
  });
}
