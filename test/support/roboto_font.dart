import 'dart:io';

import 'package:flutter/services.dart';

/// Папка со шрифтами Material внутри Flutter SDK или `null`, если её не
/// нашли. Ищем вверх от запущенного `flutter_tester`
/// (`<flutter>/bin/cache/artifacts/engine/…`).
Directory? _materialFontsDir() {
  var dir = File(Platform.resolvedExecutable).parent;
  while (dir.parent.path != dir.path) {
    final candidate = Directory(
      '${dir.path}${Platform.pathSeparator}material_fonts',
    );
    if (candidate.existsSync()) return candidate;
    dir = dir.parent;
  }
  return null;
}

/// Загружает настоящий Roboto (обычный и средний) под именем `Roboto`, каким
/// его просит тема Material на Android. Без этого тесты рисуют каждую букву
/// квадратом шириной в размер шрифта, и ширину подписи не проверить.
///
/// Возвращает `false`, если шрифтов в SDK нет (тогда тест пропускают).
Future<bool> loadRoboto() async {
  final dir = _materialFontsDir();
  if (dir == null) return false;
  final loader = FontLoader('Roboto');
  for (final name in ['roboto-regular.ttf', 'roboto-medium.ttf']) {
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    if (!file.existsSync()) return false;
    final bytes = file.readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
  return true;
}
