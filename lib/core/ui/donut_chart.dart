import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Один сектор кольца: целый вес (доля считается от суммы весов) и цвет.
class DonutSegment {
  const DonutSegment({required this.weight, required this.color});

  final int weight;
  final Color color;
}

/// Зазор между секторами, dp.
const double _gapDp = 2;

/// Насколько подсвеченный сектор толще обычного (поровну внутрь и наружу), dp.
const double _highlightExtraDp = 4;

/// Толщина кольца как доля стороны виджета.
const double _thicknessFraction = 0.16;

const double _fullTurn = 2 * math.pi;

/// Геометрия кольца: одна на рисование и на попадание, чтобы они совпадали.
///
/// Обычное кольцо лежит между [inner] и [outer]; подсвеченный сектор
/// выступает за них на половину [_highlightExtraDp] в каждую сторону и как раз
/// помещается в квадрат виджета.
class _Ring {
  _Ring(Size size) {
    final side = math.min(size.width, size.height);
    center = Offset(size.width / 2, size.height / 2);
    outer = math.max(0, side / 2 - _highlightExtraDp / 2);
    thickness = math.min(outer, side * _thicknessFraction);
    inner = outer - thickness;
  }

  late final Offset center;
  late final double outer;
  late final double inner;
  late final double thickness;

  double get middle => outer - thickness / 2;
}

/// Номер сектора под точкой [point] или `null` (дырка, за краем, нет весов).
///
/// Углы считаются от «12 часов» по часовой стрелке. Нулевые и отрицательные
/// веса секторов не получают. Правило границы: сектор включает свой начальный
/// угол и не включает конечный, то есть точка ровно на границе принадлежит
/// следующему сектору (по часовой). Зазоры при попадании игнорируются: палец
/// не должен «проваливаться» в двухпиксельную щель.
int? sectorIndexAt(Offset point, Size size, List<int> weights) {
  final total = weights.fold<int>(0, (sum, w) => w > 0 ? sum + w : sum);
  if (total == 0) return null;
  final ring = _Ring(size);
  final dx = point.dx - ring.center.dx;
  final dy = point.dy - ring.center.dy;
  final distance = math.sqrt(dx * dx + dy * dy);
  if (distance < ring.inner || distance > ring.outer) return null;

  var angle = math.atan2(dx, -dy);
  if (angle < 0) angle += _fullTurn;
  final target = angle / _fullTurn * total;
  var from = 0;
  int? lastPositive;
  for (var i = 0; i < weights.length; i++) {
    if (weights[i] <= 0) continue;
    lastPositive = i;
    from += weights[i];
    if (target < from) return i;
  }
  // Защита от погрешности на самом конце круга.
  return lastPositive;
}

/// Кольцевая диаграмма. О деньгах и категориях не знает: только веса и цвета.
///
/// Занимает квадрат по ширине, которую дал родитель. Для скринридера вся
/// диаграмма (вместе с [center]) читается одной подписью [semanticsLabel].
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.segments,
    required this.semanticsLabel,
    this.highlightedIndex,
    this.center,
    this.emptyColor,
    this.onHighlight,
    this.onSelect,
  });

  final List<DonutSegment> segments;
  final int? highlightedIndex;
  final Widget? center;
  final String semanticsLabel;

  /// Цвет серого кольца без данных; по умолчанию `outlineVariant` темы.
  final Color? emptyColor;

  /// Подсветка сектора пальцем: номер или `null` (снять). Подсветку хранит
  /// родитель и возвращает её в [highlightedIndex].
  final ValueChanged<int?>? onHighlight;

  /// Сектор выбран: короткое нажатие или отпускание пальца на секторе.
  final ValueChanged<int>? onSelect;

  int? _hit(BuildContext context, Offset point) =>
      sectorIndexAt(point, context.size!, [for (final s in segments) s.weight]);

  void _highlight(int? index) {
    if (index != highlightedIndex) onHighlight?.call(index);
  }

  /// Конец жеста: выбрать сектор под пальцем (если он есть) и снять подсветку.
  void _finish(BuildContext context, Offset point) {
    final index = _hit(context, point);
    if (index != null) onSelect?.call(index);
    onHighlight?.call(null);
  }

  @override
  Widget build(BuildContext context) {
    final painter = _DonutPainter(
      segments: segments,
      highlightedIndex: highlightedIndex,
      emptyColor: emptyColor ?? Theme.of(context).colorScheme.outlineVariant,
    );
    final interactive = onHighlight != null || onSelect != null;
    // Tap + long press (а не pan): вертикальная прокрутка родителя выигрывает
    // арену жестов, пока не сработало долгое нажатие.
    return Semantics(
      container: true,
      label: semanticsLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: interactive
            ? (d) => _highlight(_hit(context, d.localPosition))
            : null,
        onTapUp: interactive ? (d) => _finish(context, d.localPosition) : null,
        onTapCancel: interactive ? () => _highlight(null) : null,
        onLongPressStart: interactive
            ? (d) => _highlight(_hit(context, d.localPosition))
            : null,
        onLongPressMoveUpdate: interactive
            ? (d) => _highlight(_hit(context, d.localPosition))
            : null,
        onLongPressEnd: interactive
            ? (d) => _finish(context, d.localPosition)
            : null,
        onLongPressCancel: interactive ? () => _highlight(null) : null,
        child: AspectRatio(
          aspectRatio: 1,
          child: CustomPaint(
            painter: painter,
            child: Center(child: center),
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({
    required this.segments,
    required this.highlightedIndex,
    required this.emptyColor,
  });

  final List<DonutSegment> segments;
  final int? highlightedIndex;
  final Color emptyColor;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = _Ring(size);
    if (ring.thickness <= 0) return;
    final rect = Rect.fromCircle(center: ring.center, radius: ring.middle);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ring.thickness;

    final visible = <int>[
      for (var i = 0; i < segments.length; i++)
        if (segments[i].weight > 0) i,
    ];
    if (visible.isEmpty) {
      paint.color = emptyColor;
      canvas.drawArc(rect, 0, _fullTurn, false, paint);
      return;
    }
    final total = visible.fold<int>(0, (sum, i) => sum + segments[i].weight);
    if (visible.length == 1) {
      final i = visible.single;
      paint
        ..color = segments[i].color
        ..strokeWidth = ring.thickness + (i == highlightedIndex ? 4 : 0);
      canvas.drawArc(rect, 0, _fullTurn, false, paint);
      return;
    }

    final gap = _gapDp / ring.middle;
    var start = -math.pi / 2;
    for (final i in visible) {
      final sweep = segments[i].weight / total * _fullTurn;
      paint
        ..color = segments[i].color
        ..strokeWidth =
            ring.thickness + (i == highlightedIndex ? _highlightExtraDp : 0);
      final drawSweep = math.max(0.0, sweep - gap);
      canvas.drawArc(rect, start + gap / 2, drawSweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.highlightedIndex != highlightedIndex ||
      old.emptyColor != emptyColor ||
      !_sameSegments(old.segments, segments);

  static bool _sameSegments(List<DonutSegment> a, List<DonutSegment> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].weight != b[i].weight || a[i].color != b[i].color) return false;
    }
    return true;
  }
}
