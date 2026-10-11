import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:money_app/core/money/nice_ceiling.dart';
import 'package:money_app/core/ui/donut_chart.dart' show donutHoldDelay;

/// Место сверху под подпись верха шкалы, dp.
const double barChartLabelHeight = 16;

/// Доля ширины слота, которую занимает сам столбик (остальное — зазор).
const double _barFraction = 0.7;

/// Непрозрачность приглушённых столбиков, когда есть подсветка: заметно
/// бледнее выбранного, чтобы выбор виден сразу.
const double _mutedAlpha = 0.45;

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
///
/// Касания устроены как у кольца: подсветка с первого касания, палец ведёт её
/// по столбикам, реальная прокрутка родителя снимает подсветку, а удержание
/// [donutHoldDelay] останавливает прокрутку. Для скринридера весь график —
/// один узел с подписью [semanticsLabel] (её собирает вызывающий).
class BarChart extends StatefulWidget {
  const BarChart({
    super.key,
    required this.weights,
    required this.color,
    required this.topLabel,
    required this.semanticsLabel,
    this.average,
    this.highlightedIndex,
    this.onHighlight,
    this.height = 160,
  });

  final List<int> weights;
  final int? average;
  final Color color;
  final String topLabel;
  final String semanticsLabel;
  final int? highlightedIndex;

  /// Подсветка столбика пальцем: номер или `null` (снять). Подсветку хранит
  /// родитель и возвращает её в [highlightedIndex].
  final ValueChanged<int?>? onHighlight;
  final double height;

  @override
  State<BarChart> createState() => _BarChartState();
}

class _BarChartState extends State<BarChart> {
  int? _pointer;
  int? _lastHighlight;
  ScrollPosition? _position;
  double _startPixels = 0;
  bool _scrolled = false;

  int? _hit(Offset point) {
    final size = context.size;
    if (size == null) return null;
    return barIndexAt(point, size, widget.weights);
  }

  void _highlight(int? index) {
    if (index == _lastHighlight) return;
    _lastHighlight = index;
    widget.onHighlight?.call(index);
  }

  /// Родитель реально поехал: отдаём жест прокрутке, подсветку снимаем.
  void _onScrolled() {
    if (_scrolled || _pointer == null) return;
    if (_position!.pixels == _startPixels) return;
    _scrolled = true;
    _highlight(null);
  }

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _lastHighlight = widget.highlightedIndex;
    _position = Scrollable.maybeOf(context)?.position;
    _startPixels = _position?.pixels ?? 0;
    _scrolled = false;
    _position?.addListener(_onScrolled);
    _highlight(_hit(e.localPosition));
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer || _scrolled) return;
    _highlight(_hit(e.localPosition));
  }

  void _end(PointerEvent e) {
    if (e.pointer != _pointer) return;
    _reset();
    _highlight(null);
  }

  void _reset() {
    _position?.removeListener(_onScrolled);
    _position = null;
    _pointer = null;
  }

  @override
  void dispose() {
    _reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final interactive = widget.onHighlight != null;
    return Semantics(
      container: true,
      label: widget.semanticsLabel,
      excludeSemantics: true,
      // Долгое нажатие само ничего не делает: оно выигрывает арену жестов у
      // прокрутки родителя, если палец полежал [donutHoldDelay] (как у кольца).
      child: RawGestureDetector(
        excludeFromSemantics: true,
        gestures: {
          if (interactive)
            LongPressGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<
                  LongPressGestureRecognizer
                >(
                  () => LongPressGestureRecognizer(
                    duration: donutHoldDelay,
                    debugOwner: this,
                  ),
                  (recognizer) => recognizer.onLongPress = () {},
                ),
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: interactive ? _down : null,
          onPointerMove: interactive ? _move : null,
          onPointerUp: interactive ? _end : null,
          onPointerCancel: interactive ? _end : null,
          child: SizedBox(
            height: widget.height,
            width: double.infinity,
            child: CustomPaint(
              painter: _BarPainter(
                weights: widget.weights,
                average: widget.average,
                color: widget.color,
                lineColor: muted,
                topLabel: widget.topLabel,
                labelStyle: (theme.textTheme.labelSmall ?? const TextStyle())
                    .copyWith(color: muted),
                highlightedIndex: widget.highlightedIndex,
              ),
            ),
          ),
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
    label.dispose();

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
