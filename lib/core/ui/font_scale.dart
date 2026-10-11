import 'package:flutter/widgets.dart';

/// Масштаб шрифта экрана, как его видит обычный текст (14 sp).
///
/// С Android 14 системный масштаб нелинейный: крупный текст растёт слабее
/// мелкого. Поэтому везде меряем один и тот же размер, 14 sp, а не 1 или 100.
double fontScaleOf(BuildContext context) =>
    fontScaleFrom(MediaQuery.textScalerOf(context));

/// Наибольший масштаб подписей графиков (ADR 0013, п. 8): крупнее подписи
/// налезают друг на друга.
const double chartLabelMaxScale = 1.3;

/// Масштаб текста системы, ограниченный [chartLabelMaxScale]: при 200 % подписи
/// графиков такие же, как при 130 %.
TextScaler chartLabelScalerOf(BuildContext context) =>
    MediaQuery.textScalerOf(context).clamp(maxScaleFactor: chartLabelMaxScale);

/// То же для готового [TextScaler] (когда контекст недоступен).
double fontScaleFrom(TextScaler scaler) => scaler.scale(14) / 14;

/// С какого масштаба строки списков становятся двухэтажными: название, под
/// ним сумма (design-style.md, 8.6; ADR 0013, Д1).
const double twoLineRowScale = 1.3;

/// Нужна ли двухэтажная строка при текущем масштабе шрифта.
bool useTwoLineRows(BuildContext context) =>
    fontScaleOf(context) >= twoLineRowScale;
