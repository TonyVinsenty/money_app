import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Переключатель нарисован «по-айфонному»: дорожка 51 × 31 со скруглением
/// 15,5, как у системного. `Switch.adaptive` в этой версии Flutter рисует вид
/// iOS сам, без `CupertinoSwitch` внутри, поэтому проверяем по рисованию.
/// Положение дорожки зависит от отступов строки, поэтому смотрим на размер.
PaintPattern get paintsIosSwitchTrack => _trackWithRadius(15.5);

/// Дорожка Material 3 (Android): 52 × 32, скругление 16.
PaintPattern get paintsMaterialSwitchTrack => _trackWithRadius(16);

/// Дорожка: скругление [radius], ширина на 20 больше высоты (51 × 31, 52 × 32).
PaintPattern _trackWithRadius(double radius) =>
    paints..something((method, arguments) {
      if (method != #drawRRect) return false;
      final rrect = arguments.first as RRect;
      return rrect.tlRadiusX == radius && rrect.width == 2 * radius + 20;
    });
