import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:money_app/core/money/nice_ceiling.dart';

/// Место сверху под подпись верха шкалы, dp.
const double barChartLabelHeight = 16;

/// Доля ширины слота, которую занимает сам столбик (остальное — зазор).
const double _barFraction = 0.7;

/// Непрозрачность приглушённых столбиков, когда есть подсветка.
const double _mutedAlpha = 0.75;

/// Нижняя граница высоты ненулевого столбика, dp: чтобы малая сумма была видна.
const double _minBarHeightDp = 1;

/// Верх шкалы: «круглое» число не меньше самого большого веса и среднего.
int barChartCeiling(List<int> weights, [int? average]) {
  var top = average ?? 0;
  for (final w in weights) {
    if (w > top) top = w;
  }
  return niceCeiling(top);
}

/// Область столбиков: весь [size] без полосы под подпись шкалы сверху.
Rect _plot(Size size) => Rect.fromLTRB(
  0,
  math.min(barChartLabelHeight, size.height),
  size.width,
  size.height,
);

/// Прямоугольники столбиков, по одному на вес, слева направо.
///
/// Ширина делится на равные слоты, столбик занимает по центру 70 % слота.
/// Высота пропорциональна весу относительно [barChartCeiling]. Нулевой и
/// отрицательный вес — прямоугольник нулевой высоты на нижней линии; ненулевой
/// не ниже 1 dp. Нет весов — пустой список.
List<Rect> barRects(Size size, List<int> weights, [int? average]) {
  if (weights.isEmpty) return const [];
  final plot = _plot(size);
  final top = barChartCeiling(weights, average);
  final slot = plot.width / weights.length;
  final barWidth = slot * _barFraction;
  return [
    for (var i = 0; i < weights.length; i++)
      () {
        final raw = weights[i] <= 0
            ? 0.0
            : math.max(_minBarHeightDp, weights[i] / top * plot.height);
        final h = math.min(raw, plot.height);
        return Rect.fromLTWH(
          plot.left + slot * i + (slot - barWidth) / 2,
          plot.bottom - h,
          barWidth,
          h,
        );
      }(),
  ];
}

/// Координата y линии среднего (ниже по экрану — больше).
double barAverageY(Size size, List<int> weights, int average) {
  final plot = _plot(size);
  final top = barChartCeiling(weights, average);
  return plot.bottom - average.clamp(0, top) / top * plot.height;
}

/// Номер столбика под точкой [point] или `null`, если точка за пределами
/// [size] или весов нет.
///
/// Между столбиками (в зазоре) побеждает ближайший по x, то есть попадание
/// считается по целому слоту. Высота не важна: касание над низким или нулевым
/// столбиком тоже выбирает его (палец водят по всей ширине графика).
int? barIndexAt(Offset point, Size size, List<int> weights) {
  if (weights.isEmpty) return null;
  if (point.dx < 0 || point.dx > size.width) return null;
  if (point.dy < 0 || point.dy > size.height) return null;
  final slot = size.width / weights.length;
  return math.min(weights.length - 1, (point.dx / slot).floor());
}

/// Цвет столбика [index]: при подсветке остальные приглушены.
Color barColor(Color base, int index, int? highlighted) =>
    highlighted == null || highlighted == index
    ? base
    : base.withValues(alpha: _mutedAlpha);

/// Столбчатый график. О деньгах не знает: веса, цвет и готовая подпись верха
/// шкалы ([topLabel], её форматирует вызывающий). Высоту задаёт [height],
/// ширина — вся доступная.
class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.weights,
    required this.color,
    required this.topLabel,
    this.average,
    this.highlightedIndex,
    this.height = 160,
  });

  final List<int> weights;
  final int? average;
  final Color color;
  final String topLabel;
  final int? highlightedIndex;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _BarPainter(
          weights: weights,
          average: average,
          color: color,
          lineColor: muted,
          topLabel: topLabel,
          labelStyle: (theme.textTheme.labelSmall ?? const TextStyle())
              .copyWith(color: muted),
          highlightedIndex: highlightedIndex,
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.weights,
    required this.average,
    required this.color,
    required this.lineColor,
    required this.topLabel,
    required this.labelStyle,
    required this.highlightedIndex,
  });

  final List<int> weights;
  final int? average;
  final Color color;
  final Color lineColor;
  final String topLabel;
  final TextStyle labelStyle;
  final int? highlightedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final label = TextPainter(
      text: TextSpan(text: topLabel, style: labelStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: size.width);
    label.paint(canvas, Offset.zero);

    final rects = barRects(size, weights, average);
    final radius = Radius.circular(math.min(2, size.width / 4));
    for (var i = 0; i < rects.length; i++) {
      if (rects[i].height <= 0) continue;
      canvas.drawRRect(
        RRect.fromRectAndCorners(rects[i], topLeft: radius, topRight: radius),
        Paint()..color = barColor(color, i, highlightedIndex),
      );
    }

    final avg = average;
    if (avg != null && avg > 0) {
      final y = barAverageY(size, weights, avg);
      final paint = Paint()
        ..color = lineColor
        ..strokeWidth = 1.5;
      for (var x = 0.0; x < size.width; x += 8) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 4, size.width), y),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.average != average ||
      old.color != color ||
      old.lineColor != lineColor ||
      old.topLabel != topLabel ||
      old.labelStyle != labelStyle ||
      old.highlightedIndex != highlightedIndex ||
      !_sameWeights(old.weights, weights);

  static bool _sameWeights(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
