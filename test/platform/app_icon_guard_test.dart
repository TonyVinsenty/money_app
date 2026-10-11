// Сторож иконки Android (шаг 7.2, ADR 0013): адаптивная иконка, векторные слои
// и PNG для старых Android проверяем текстом и размерами файлов.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _res = 'android/app/src/main/res';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('adaptive icon has background, foreground and monochrome', () {
    final xml = _read('$_res/mipmap-anydpi-v26/ic_launcher.xml');
    expect(xml, contains('<adaptive-icon'));
    expect(xml, contains('@color/ic_launcher_background'));
    expect(xml, contains('@drawable/ic_launcher_foreground'));
    expect(xml, contains('<monochrome'));
    expect(xml, contains('@drawable/ic_launcher_monochrome'));
  });

  test('background color is F3F5F6', () {
    final xml = _read('$_res/values/ic_launcher_background.xml');
    expect(xml, contains('name="ic_launcher_background"'));
    expect(xml, contains('#F3F5F6'));
  });

  for (final name in ['ic_launcher_foreground', 'ic_launcher_monochrome']) {
    test('$name has three trimmed arcs', () {
      final xml = _read('$_res/drawable/$name.xml');
      expect('<path'.allMatches(xml).length, 3);
      expect('android:trimPathStart'.allMatches(xml).length, 3);
      expect('android:trimPathEnd'.allMatches(xml).length, 3);
    });
  }

  test('legacy PNG icons exist with expected sizes', () {
    const sizes = {
      'mdpi': 48,
      'hdpi': 72,
      'xhdpi': 96,
      'xxhdpi': 144,
      'xxxhdpi': 192,
    };
    sizes.forEach((density, px) {
      final file = File('$_res/mipmap-$density/ic_launcher.png');
      expect(file.existsSync(), isTrue, reason: density);
      final b = file.readAsBytesSync();
      final w = (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];
      final h = (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23];
      expect([w, h], [px, px], reason: density);
    });
  });

  test('manifest references @mipmap/ic_launcher', () {
    final m = _read('android/app/src/main/AndroidManifest.xml');
    expect(m, contains('android:icon="@mipmap/ic_launcher"'));
  });
}
