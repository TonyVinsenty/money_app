// Сторож канала «Поделиться» (шаг i.6, ADR 0009). Нативный код Android и iOS
// мы на Windows не собираем, поэтому проверяем текстом: имя канала и метода
// должны совпадать с Dart-стороной, а ошибки и точка привязки для iPad — быть
// на месте. Образец — ios_project_guard_test.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/settings/presentation/share_csv_file.dart';

/// Общие проверки для обеих платформ. Возвращает список ошибок.
List<String> checkShareCommon(String source) {
  final errors = <String>[];
  for (final needle in [
    '"${shareChannel.name}"',
    '"$shareCsvFileMethod"',
    '"$shareCsvFilePathArg"',
    '"file_not_found"',
    '"bad_args"',
  ]) {
    if (!source.contains(needle)) errors.add('Не найдено $needle');
  }
  return errors;
}

/// Проверки только для Swift: канал создаётся внутри
/// `didInitializeImplicitFlutterEngine`, задана точка привязки для iPad.
List<String> checkShareSwift(String source) {
  final errors = checkShareCommon(source);
  // Тело метода: от его заголовка до следующего `func` (или до конца файла).
  final start = source.indexOf('func didInitializeImplicitFlutterEngine');
  var end = start < 0 ? -1 : source.indexOf('func ', start + 5);
  if (start >= 0 && end < 0) end = source.length;
  final body = start < 0 ? '' : source.substring(start, end);
  if (!body.contains('FlutterMethodChannel(')) {
    errors.add('Канал не создаётся в didInitializeImplicitFlutterEngine');
  }
  if (!source.contains('popoverPresentationController') ||
      !source.contains('.sourceView =')) {
    errors.add('Нет точки привязки popover (падение на iPad)');
  }
  return errors;
}

void main() {
  final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
  final kotlin = File(
    'android/app/src/main/kotlin/com/tonyvinsenty/zuno/MainActivity.kt',
  ).readAsStringSync();

  test('AppDelegate.swift: канал, метод, ошибки и popover для iPad', () {
    expect(checkShareSwift(swift), isEmpty);
  });

  test('MainActivity.kt: канал, метод и ошибки', () {
    expect(checkShareCommon(kotlin), isEmpty);
  });

  group('сам сторож распознаёт нарушения (синтетический текст)', () {
    String good({String channel = 'com.tonyvinsenty.zuno/share'}) =>
        '''
func didInitializeImplicitFlutterEngine(_ b: X) {
  FlutterMethodChannel(name: "$channel")
}
func other() {
  "shareCsvFile" "path" "file_not_found" "bad_args"
  popoverPresentationController popover.sourceView = v
}
''';

    test('чистый текст проходит', () {
      expect(checkShareSwift(good()), isEmpty);
    });

    test('другое имя канала — ошибка', () {
      expect(checkShareSwift(good(channel: 'other/share')), isNotEmpty);
    });

    test('канал вне didInitializeImplicitFlutterEngine — ошибка', () {
      final bad = good().replaceFirst('FlutterMethodChannel(', 'Other(');
      expect(checkShareSwift(bad), isNotEmpty);
    });

    test('нет popover — ошибка', () {
      final bad = good().replaceFirst('popoverPresentationController', '');
      expect(checkShareSwift(bad), isNotEmpty);
    });

    test('popover без sourceView — ошибка', () {
      final bad = good().replaceFirst('.sourceView =', '');
      expect(checkShareSwift(bad), isNotEmpty);
    });

    test('другой ключ пути — ошибка', () {
      final bad = good().replaceFirst('"path"', '"file"');
      expect(checkShareSwift(bad), isNotEmpty);
    });
  });
}
