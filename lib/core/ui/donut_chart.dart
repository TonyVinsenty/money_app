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
class DonutChart extends StatefulWidget {
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

  /// Сектор выбран: отпускание пальца на секторе (в том числе короткое
  /// нажатие), даже если палец до этого переезжал между секторами.
  final ValueChanged<int>? onSelect;

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart> {
  /// Палец, за которым следим (первый); остальные игнорируются.
  int? _pointer;

  /// Что мы последним сообщили родителю через onHighlight.
  int? _lastHighlight;

  /// Прокрутка родителя, в которой палец лежит с момента касания.
  ScrollPosition? _position;
  double _startPixels = 0;
  bool _scrolled = false;

  int? _hit(Offset point) {
    final size = context.size;
    if (size == null) return null;
    return sectorIndexAt(point, size, [
      for (final s in widget.segments) s.weight,
    ]);
  }

  void _highlight(int? index) {
    if (index == _lastHighlight) return;
    _lastHighlight = index;
    widget.onHighlight?.call(index);
  }

  void _watchScroll() {
    _position = Scrollable.maybeOf(context)?.position;
    _startPixels = _position?.pixels ?? 0;
    _scrolled = false;
    _position?.addListener(_onScrolled);
  }

  void _unwatchScroll() {
    _position?.removeListener(_onScrolled);
    _position = null;
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
    _watchScroll();
    _highlight(_hit(e.localPosition));
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer || _scrolled) return;
    _highlight(_hit(e.localPosition));
  }

  void _up(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    final selected = _scrolled ? null : _hit(e.localPosition);
    _reset();
    if (selected != null) widget.onSelect?.call(selected);
    _highlight(null);
  }

  void _cancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    _reset();
    _highlight(null);
  }

  void _reset() {
    _unwatchScroll();
    _pointer = null;
  }

  @override
  void dispose() {
    // Палец ещё может лежать на экране: его события дойдут до удалённого
    // виджета, поэтому «следим за пальцем» тоже сбрасываем.
    _reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final painter = _DonutPainter(
      segments: widget.segments,
      highlightedIndex: widget.highlightedIndex,
      emptyColor:
          widget.emptyColor ?? Theme.of(context).colorScheme.outlineVariant,
    );
    final interactive = widget.onHighlight != null || widget.onSelect != null;
    // Listener (сырые события), а не GestureDetector: он видит палец всегда,
    // независимо от арены жестов, и подсветка следует за ним с первого
    // касания. Прокрутку родителя узнаём по сдвигу его позиции; если
    // прокручивать нечего, Scrollable жест не забирает (нет распознавателей).
    return Semantics(
      container: true,
      label: widget.semanticsLabel,
      excludeSemantics: true,
      // Долгое нажатие само ничего не делает: оно выигрывает арену жестов у
      // прокрутки родителя, если палец полежал на месте. После этого экран
      // стоит, и палец свободно ходит между секторами. На iOS прокрутка
      // «пружинит» даже без лишнего содержимого и иначе забирала бы жест.
      child: GestureDetector(
        excludeFromSemantics: true,
        onLongPress: interactive ? () {} : null,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: interactive ? _down : null,
          onPointerMove: interactive ? _move : null,
          onPointerUp: interactive ? _up : null,
          onPointerCancel: interactive ? _cancel : null,
          child: AspectRatio(
            aspectRatio: 1,
            child: CustomPaint(
              painter: painter,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final center = widget.center;
                  if (center == null) return const SizedBox.shrink();
                  // Центр живёт во вписанном квадрате дырки (диаметр дырки
                  // на 0.71): шире и выше не бывает, большее ужимается.
                  final side = _Ring(constraints.biggest).inner * 2 * 0.71;
                  return Center(
                    child: SizedBox.square(
                      dimension: side,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: side),
                          child: center,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
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
        ..strokeWidth =
            ring.thickness + (i == highlightedIndex ? _highlightExtraDp : 0);
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
