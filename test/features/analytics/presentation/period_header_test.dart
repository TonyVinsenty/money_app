import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/period_switcher.dart';
import 'package:money_app/features/analytics/presentation/period_header.dart';

Widget _app({
  PeriodKind kind = PeriodKind.month,
  ValueChanged<PeriodKind>? onKind,
  VoidCallback? onCustom,
  double scale = 1,
  double width = 360,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 800),
        textScaler: TextScaler.linear(scale),
      ),
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: PeriodHeader(
            kind: kind,
            label: 'Октябрь 2026',
            onKindSelected: onKind ?? (_) {},
            onCustomSelected: onCustom ?? () {},
            onPrevious: () {},
            onNext: null,
            previousTooltip: 'Предыдущий месяц',
            nextTooltip: 'Следующий месяц',
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('выбор пункта зовёт колбэк вида', (tester) async {
    PeriodKind? got;
    await tester.pumpWidget(_app(onKind: (k) => got = k));
    await tester.tap(find.byKey(PeriodHeader.kindButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PeriodHeader.itemKey(PeriodKind.week)));
    await tester.pumpAndSettle();
    expect(got, PeriodKind.week);
  });

  testWidgets('«Свой период…» зовёт свой колбэк', (tester) async {
    var custom = 0;
    PeriodKind? got;
    await tester.pumpWidget(
      _app(onKind: (k) => got = k, onCustom: () => custom++),
    );
    await tester.tap(find.byKey(PeriodHeader.kindButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PeriodHeader.customItemKey));
    await tester.pumpAndSettle();
    expect(custom, 1);
    expect(got, isNull);
  });

  testWidgets('выбранный пункт отмечен галочкой', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.byKey(PeriodHeader.kindButtonKey));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(PeriodHeader.itemKey(PeriodKind.month)),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
  });

  testWidgets('озвучка кнопки вида', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app());
    expect(find.bySemanticsLabel('Период: месяц, изменить'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('200 % на 360 dp: без overflow, вид над стрелками', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(scale: 2));
    expect(tester.takeException(), isNull);
    final button = tester.getRect(find.byKey(PeriodHeader.kindButtonKey));
    final switcher = tester.getRect(find.byType(PeriodSwitcher));
    expect(button.bottom, lessThanOrEqualTo(switcher.top));
    expect(switcher.right, lessThanOrEqualTo(360));
  });

  testWidgets('100 %: всё в одной строке', (tester) async {
    await tester.pumpWidget(_app());
    final button = tester.getRect(find.byKey(PeriodHeader.kindButtonKey));
    final switcher = tester.getRect(find.byType(PeriodSwitcher));
    expect(button.right, lessThanOrEqualTo(switcher.left));
    expect(button.center.dy, closeTo(switcher.center.dy, 1));
  });
}
