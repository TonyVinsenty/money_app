import 'package:flutter/widgets.dart';
import 'package:money_app/core/ui/font_scale.dart';
import 'package:money_app/features/home/presentation/month_chart_card.dart';

/// Шире этого экран не телефон (планшет, окно): компактный режим не нужен.
const double compactHomeMaxWidth = 500;

/// Кольцо меньше этого (dp) в обычном режиме — пора включать компактный.
const double compactHomeMinRing = 200;

/// Высота панели кнопок (64 + отступы 2 x 16), капсулы навигации и зазора под
/// ней, dp: из них вычитаем высоту видимой области «Главной».
const double _actionBarHeight = 96;
const double _navHeight = 64 + 8;

/// Компактный режим «Главной»: легенда одной строкой, кнопки «Доход/Расход»
/// ниже (56 dp вместо 64). Включается, если кольцо в обычном режиме по высоте
/// получилось бы меньше [compactHomeMinRing]. Решение одно для карточки,
/// расчёта кольца и панели кнопок: они лежат в разных местах дерева, поэтому
/// считаем по размеру окна и системным отступам окна, а не по их MediaQuery.
bool isCompactHome(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  if (size.width >= compactHomeMaxWidth) return false;
  final system = MediaQueryData.fromView(View.of(context)).padding;
  // Видимая область: без системных панелей, отступа 16 сверху и кнопок с
  // навигацией (плашку «К оплате» не учитываем).
  final viewportHeight =
      size.height -
      system.top -
      system.bottom -
      16 -
      _actionBarHeight -
      _navHeight;
  final ring = chartRingSize(
    viewportWidth: size.width - 32,
    viewportHeight: viewportHeight,
    textScale: fontScaleOf(context),
    fitHeightOnly: true,
  );
  return ring < compactHomeMinRing;
}
