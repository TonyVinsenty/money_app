import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Знак Zuno — кольцо из трёх долей, как на иконке приложения (вариант 1
/// «Кольцо крупнее», ADR 0014): синяя, оранжевая и фиолетовая доли по
/// часовой стрелке от верха, с зазорами. Только для глаз — в озвучке его нет.
class ZunoMark extends StatelessWidget {
  const ZunoMark({this.size = 48, super.key});

  /// Внешний диаметр кольца.
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: CustomPaint(
      size: Size.square(size),
      painter: const ZunoMarkPainter(),
    ),
  );
}

/// Рисует [ZunoMark]: пропорции и доли — как в `ic_launcher_foreground.xml`
/// варианта 1 (радиус 250 и толщина 120 на поле 1024, внешний диаметр 620).
class ZunoMarkPainter extends CustomPainter {
  const ZunoMarkPainter();

  /// Доли кольца: начало и конец в долях окружности и цвет.
  static const segments = <(double, double, Color)>[
    (0, 0.425, Color(0xFF2F6FD6)),
    (0.455, 0.725, Color(0xFFE9823A)),
    (0.755, 0.97, Color(0xFF7B57C9)),
  ];

  /// Толщина кольца относительно внешнего диаметра (120 / 620).
  static const strokeRatio = 120 / 620;

  @override
  void paint(Canvas canvas, Size size) {
    final diameter = math.min(size.width, size.height);
    final stroke = diameter * strokeRatio;
    final radius = (diameter - stroke) / 2;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: radius,
    );
    for (final (start, end, color) in segments) {
      canvas.drawArc(
        rect,
        -math.pi / 2 + start * 2 * math.pi,
        (end - start) * 2 * math.pi,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke
          ..strokeCap = StrokeCap.butt
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(ZunoMarkPainter oldDelegate) => false;
}
