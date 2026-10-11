import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals, mapEquals;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:money_app/core/money/nice_ceiling.dart';
import 'package:money_app/core/ui/donut_chart.dart' show donutHoldDelay;
import 'package:money_app/core/ui/font_scale.dart';

/// Место сверху под подпись верха шкалы, dp.
const double barChartLabelHeight = 16;

/// Высота полосы подписей оси под столбиками, dp (если подписи есть).
const double barChartAxisHeight = 16;

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

/// Значения шкалы снизу вверх: 0, середина и верх ([barChartCeiling]).
List<int> barScaleValues(List<int> weights, [int? average]) {
  final top = barChartCeiling(weights, average);
  return [0, top ~/ 2, top];
}

/// Область столбиков: весь [size] без полосы под подпись шкалы сверху, без
/// полосы подписей оси снизу ([axisHeight], 0 — подписей нет) и без отступа
/// слева под подписи шкалы ([leftInset], 0 — подписей слева нет).
Rect _plot(Size size, double axisHeight, [double leftInset = 0]) {
  final top = math.min(barChartLabelHeight, size.height);
  return Rect.fromLTRB(
    math.min(leftInset, size.width),
    top,
    size.width,
    math.max(top, size.height - axisHeight),
  );
}

/// Прямоугольники столбиков, по одному на вес, слева направо.
///
/// Ширина делится на равные слоты, столбик занимает по центру 70 % слота.
/// Высота пропорциональна весу относительно [barChartCeiling]. Нулевой и
/// отрицательный вес — прямоугольник нулевой высоты на нижней линии; ненулевой
/// не ниже 1 dp. Нет весов — пустой список. Если есть подписи оси, передают
/// [axisHeight] ([barChartAxisHeight]): столбики кончаются выше на эту полосу.
List<Rect> barRects(
  Size size,
  List<int> weights, [
  int? average,
  double axisHeight = 0,
  double leftInset = 0,
]) {
  if (weights.isEmpty) return const [];
  final plot = _plot(size, axisHeight, leftInset);
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
double barAverageY(
  Size size,
  List<int> weights,
  int average, [
  double axisHeight = 0,
  double leftInset = 0,
]) {
  final plot = _plot(size, axisHeight, leftInset);
  final top = barChartCeiling(weights, average);
  return plot.bottom - average.clamp(0, top) / top * plot.height;
}

/// Координата y значения шкалы [value] (0 — низ, верх шкалы — вверху области).
double barScaleY(
  Size size,
  List<int> weights,
  int value, [
  int? average,
  double axisHeight = 0,
]) {
  final plot = _plot(size, axisHeight);
  final top = barChartCeiling(weights, average);
  return plot.bottom - value.clamp(0, top) / top * plot.height;
}

/// Левый край подписи шириной [width] по центру слота [index] из [count],
/// сдвинутый внутрь, если вылезает за [totalWidth]. Слоты начинаются с
/// отступа [leftInset].
double barAxisLabelLeft(
  int index,
  int count,
  double totalWidth,
  double width, [
  double leftInset = 0,
]) {
  final center = leftInset + (totalWidth - leftInset) / count * (index + 0.5);
  final half = width / 2;
  final lo = leftInset + half;
  return center.clamp(lo, math.max(lo, totalWidth - half)) - half;
}

/// Номер столбика под точкой [point] или `null`, если точка за пределами
/// [size] или весов нет.
///
/// Между столбиками (в зазоре) побеждает ближайший по x, то есть попадание
/// считается по целому слоту. Высота не важна: касание над низким или нулевым
/// столбиком тоже выбирает его (палец водят по всей ширине графика).
int? barIndexAt(
  Offset point,
  Size size,
  List<int> weights, [
  double leftInset = 0,
]) {
  if (weights.isEmpty) return null;
  if (point.dx < 0 || point.dx > size.width) return null;
  if (point.dy < 0 || point.dy > size.height) return null;
  final slot = (size.width - leftInset) / weights.length;
  return math.max(
    0,
    math.min(weights.length - 1, ((point.dx - leftInset) / slot).floor()),
  );
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
///
/// [axisLabels] — необязательные подписи оси: номер столбика → короткая строка
/// (строки готовит вызывающий). Рисуются под столбиками по центру своего
/// столбика мелким шрифтом, растущим со шрифтом системы до 130 % (полоса
/// высотой [barChartAxisHeight] при 100 %, дальше растёт; значения и так есть
/// в озвучке). Подпись, которая
/// налезла бы на предыдущую, пропускается. Из семантики подписи исключены.
class BarChart extends StatefulWidget {
  const BarChart({
    super.key,
    required this.weights,
    required this.color,
    required this.topLabel,
    required this.semanticsLabel,
    this.average,
    this.axisLabels = const {},
    this.midLabel,
    this.zeroLabel,
    this.highlightedIndex,
    this.onHighlight,
    this.height = 160,
  });

  /// Подписи шкалы слева: [zeroLabel] внизу, [midLabel] посередине, [topLabel]
  /// вверху. Если заданы обе, они рисуются слева от столбиков (отступ под
  /// самую широкую), иначе [topLabel] — одна строка сверху.
  final String? midLabel;
  final String? zeroLabel;

  final List<int> weights;
  final int? average;
  final Map<int, String> axisLabels;
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
  double _leftInset = 0; // считается в build

  int? _hit(Offset point) {
    final size = context.size;
    if (size == null) return null;
    return barIndexAt(point, size, widget.weights, _leftInset);
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
    final labelStyle = (theme.textTheme.labelSmall ?? const TextStyle())
        .copyWith(color: muted);
    final scale = widget.midLabel != null && widget.zeroLabel != null
        ? [widget.zeroLabel!, widget.midLabel!, widget.topLabel]
        : const <String>[];
    final scaler = chartLabelScalerOf(context);
    _leftInset = barChartLeftInset(scale, labelStyle, scaler);
    // Полоса оси растёт вместе с подписями (при 100 % остаётся 16 dp).
    final axisHeight = widget.axisLabels.isEmpty
        ? 0.0
        : barChartAxisHeightFor(scaler);
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
                axisLabels: widget.axisLabels,
                color: widget.color,
                lineColor: muted,
                topLabel: widget.topLabel,
                scaleLabels: scale,
                leftInset: _leftInset,
                axisHeight: axisHeight,
                textScaler: scaler,
                labelStyle: labelStyle,
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
    required this.axisLabels,
    required this.color,
    required this.lineColor,
    required this.topLabel,
    required this.scaleLabels,
    required this.leftInset,
    required this.axisHeight,
    required this.textScaler,
    required this.labelStyle,
    required this.highlightedIndex,
  });

  /// Высота полосы подписей оси (0 — подписей нет) и масштаб их текста.
  final double axisHeight;
  final TextScaler textScaler;

  /// Подписи шкалы снизу вверх (пусто — одна подпись [topLabel] сверху).
  final List<String> scaleLabels;
  final double leftInset;

  final List<int> weights;
  final int? average;
  final Map<int, String> axisLabels;
  final Color color;
  final Color lineColor;
  final String topLabel;
  final TextStyle labelStyle;
  final int? highlightedIndex;

  @override
  void paint(Canvas canvas, Size size) {
    final axis = axisHeight;
    if (scaleLabels.isEmpty) {
      final label = TextPainter(
        text: TextSpan(text: topLabel, style: labelStyle),
        textScaler: textScaler,
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: size.width);
      label.paint(canvas, Offset.zero);
      label.dispose();
    } else {
      final values = barScaleValues(weights, average);
      for (var i = 0; i < scaleLabels.length; i++) {
        final p = TextPainter(
          text: TextSpan(text: scaleLabels[i], style: labelStyle),
          textScaler: textScaler,
          textDirection: TextDirection.ltr,
          maxLines: 1,
        )..layout();
        final y = barScaleY(size, weights, values[i], average, axis);
        p.paint(
          canvas,
          Offset(leftInset - 6 - p.width, math.max(0, y - p.height / 2)),
        );
        p.dispose();
      }
    }
    final rects = barRects(size, weights, average, axis, leftInset);
    final radius = Radius.circular(math.min(2, size.width / 4));
    for (var i = 0; i < rects.length; i++) {
      if (rects[i].height <= 0) continue;
      canvas.drawRRect(
        RRect.fromRectAndCorners(rects[i], topLeft: radius, topRight: radius),
        Paint()..color = barColor(color, i, highlightedIndex),
      );
    }

    if (axisLabels.isNotEmpty) _paintAxis(canvas, size);

    final avg = average;
    if (avg != null && avg > 0) {
      final y = barAverageY(size, weights, avg, axis, leftInset);
      final paint = Paint()
        ..color = lineColor
        ..strokeWidth = 1.5;
      for (var x = leftInset; x < size.width; x += 8) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 4, size.width), y),
          paint,
        );
      }
    }
  }

  /// Подписи оси слева направо; налезающая на предыдущую пропускается.
  void _paintAxis(Canvas canvas, Size size) {
    final indexes = [
      for (final i in axisLabels.keys)
        if (i >= 0 && i < weights.length) i,
    ]..sort();
    var lastRight = double.negativeInfinity;
    for (final i in indexes) {
      final p = TextPainter(
        text: TextSpan(text: axisLabels[i], style: labelStyle),
        textScaler: textScaler,
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final left = barAxisLabelLeft(
        i,
        weights.length,
        size.width,
        p.width,
        leftInset,
      );
      if (left >= lastRight + 2) {
        p.paint(canvas, Offset(left, size.height - axisHeight + 2));
        lastRight = left + p.width;
      }
      p.dispose();
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.average != average ||
      !mapEquals(old.axisLabels, axisLabels) ||
      old.color != color ||
      old.lineColor != lineColor ||
      old.topLabel != topLabel ||
      old.leftInset != leftInset ||
      old.axisHeight != axisHeight ||
      old.textScaler != textScaler ||
      !listEquals(old.scaleLabels, scaleLabels) ||
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

/// Отступ слева: самая широкая подпись шкалы (с масштабом [scaler]) и зазор
/// 6 dp; нет подписей — 0.
double barChartLeftInset(
  List<String> labels,
  TextStyle style,
  TextScaler scaler,
) {
  var widest = 0.0;
  for (final s in labels) {
    final p = TextPainter(
      text: TextSpan(text: s, style: style),
      textScaler: scaler,
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    widest = math.max(widest, p.width);
    p.dispose();
  }
  return labels.isEmpty ? 0 : widest + 6;
}

/// Высота полосы подписей оси при масштабе [scaler]: 16 dp при 100 %, дальше
/// растёт вместе с подписями.
double barChartAxisHeightFor(TextScaler scaler) =>
    barChartAxisHeight * fontScaleFrom(scaler);
