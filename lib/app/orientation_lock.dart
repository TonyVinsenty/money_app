import 'package:flutter/services.dart';

/// Закрепляет вертикальное положение экрана (решение пользователя).
///
/// Код экранов при этом не вырезается: если позже понадобится альбомная
/// ориентация, достаточно убрать этот вызов и правки в манифесте и `Info.plist`.
Future<void> lockPortraitOrientation() {
  return SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
  ]);
}
