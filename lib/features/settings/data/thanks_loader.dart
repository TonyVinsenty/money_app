import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:money_app/features/settings/domain/thanks.dart';

/// Путь к списку имён «Спасибо» в ресурсах приложения.
const thanksAssetPath = 'assets/thanks.json';

/// Читает список «Спасибо» из ресурсов приложения. Файла нет или он не
/// читается — пустой список (экран покажет заглушку).
Future<Thanks> loadThanks({AssetBundle? bundle}) async {
  try {
    final source = await (bundle ?? rootBundle).loadString(thanksAssetPath);
    return Thanks.parse(source);
  } on FlutterError {
    // Ресурса нет — Flutter бросает FlutterError, а не Exception.
    return Thanks.empty;
  } on Exception {
    return Thanks.empty;
  }
}
