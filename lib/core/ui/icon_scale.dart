import 'package:flutter/widgets.dart';

/// Во сколько раз растёт значок рядом с текстом: как шрифт, но не больше 1,3
/// (D26). При обычном шрифте — ровно 1.
double iconScaleOf(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3);
