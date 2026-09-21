import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Отношение контрастности двух цветов (WCAG). Полупрозрачный [foreground]
/// сначала кладётся на [background], как это увидит глаз.
double contrastRatio(Color foreground, Color background) {
  final shown = Color.alphaBlend(foreground, background);
  final l1 = shown.computeLuminance();
  final l2 = background.computeLuminance();
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}
