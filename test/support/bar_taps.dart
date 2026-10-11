import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/bar_chart.dart';

/// Точка по центру столбика [index] из [count] в графике [chart] на высоте
/// [dy] от его верха. Учитывает отступ слева под подписи шкалы.
Offset barSlotPoint(
  WidgetTester tester,
  Finder chart,
  int index,
  int count, {
  double dy = 100,
}) {
  final w = tester.widget<BarChart>(chart);
  var widest = 0.0;
  for (final s in [w.zeroLabel, w.midLabel, w.topLabel]) {
    if (s == null) continue;
    final p = TextPainter(
      text: TextSpan(
        text: s,
        style: Theme.of(tester.element(chart)).textTheme.labelSmall,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    if (p.width > widest) widest = p.width;
    p.dispose();
  }
  final inset = w.zeroLabel != null && w.midLabel != null ? widest + 6 : 0.0;
  final width = tester.getSize(chart).width;
  final slot = (width - inset) / count;
  return tester.getTopLeft(chart) + Offset(inset + slot * (index + 0.5), dy);
}
