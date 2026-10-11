import 'package:flutter/widgets.dart';

/// Шкала отступов (ADR 0013, п. 1; docs/design-style.md, раздел 8.1).
/// Других чисел в `EdgeInsets` и пустых `SizedBox` нет: это проверяет
/// `test/core/ui/spacing_guard_test.dart`.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 24;

  /// Отступ под аватаром: ширина иконки 24 dp и промежутка 16 dp, чтобы
  /// текст второй части строки выровнялся по названию. Совпадает с размером
  /// другого элемента, поэтому не из шкалы.
  static const double belowAvatar = 40;

  /// Ширина аватара-кружка (`CategoryAvatar`, аватар счёта): по ней текст
  /// под аватаром выравнивается по названию.
  static const double avatarWidth = 40;

  /// Запас снизу списка под кнопку «Добавить…», чтобы она не закрывала
  /// последнюю строку. Привязан к размеру кнопки, поэтому не из шкалы.
  static const double fabClearance = 96;
}

/// Скругления (раздел 8.2): 12 — поля, плитки, плашки; 16 — карточки, листы.
abstract final class AppRadius {
  static const double m = 12;
  static const double l = 16;

  static const BorderRadius borderM = BorderRadius.all(Radius.circular(m));
  static const BorderRadius borderL = BorderRadius.all(Radius.circular(l));
}
