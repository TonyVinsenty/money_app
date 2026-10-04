import 'package:flutter/widgets.dart';

/// Масштаб шрифта экрана, как его видит обычный текст (14 sp).
///
/// С Android 14 системный масштаб нелинейный: крупный текст растёт слабее
/// мелкого. Поэтому везде меряем один и тот же размер, 14 sp, а не 1 или 100.
double fontScaleOf(BuildContext context) =>
    fontScaleFrom(MediaQuery.textScalerOf(context));

/// То же для готового [TextScaler] (когда контекст недоступен).
double fontScaleFrom(TextScaler scaler) => scaler.scale(14) / 14;
