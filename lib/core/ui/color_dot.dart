import 'package:flutter/widgets.dart';

/// Круглая метка цвета в строке списка (легенда диаграммы). Для скринридера
/// пуста: смысл строки несёт её текст.
class ColorDot extends StatelessWidget {
  const ColorDot({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}
