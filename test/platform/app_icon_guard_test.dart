// Сторож иконки Android (шаг 7.2, ADR 0013): адаптивная иконка, векторные слои
// и PNG для старых Android проверяем текстом и размерами файлов.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/zuno_mark.dart';

import '../support/png_pixels.dart';

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

  // Шаг 8.35: иконка по умолчанию — вариант 1 «Кольцо крупнее» (ADR 0014).
  for (final name in ['ic_launcher_foreground', 'ic_launcher_monochrome']) {
    test('$name is variant 1: radius 26.4, stroke 12.7, inside safe zone', () {
      final xml = _read('$_res/drawable/$name.xml');
      expect(
        'M54,27.6 A26.4,26.4 0 1,1 54,80.4 A26.4,26.4 0 1,1 54,27.6'
            .allMatches(xml)
            .length,
        3,
      );
      expect('android:strokeWidth="12.7"'.allMatches(xml).length, 3);
      // Внешний диаметр 2 × 26,4 + 12,7 = 65,5 — в безопасном круге 66 dp.
      expect(2 * 26.4 + 12.7, lessThanOrEqualTo(66));
    });

    test('$name trims match the in-app Zuno mark', () {
      final xml = _read('$_res/drawable/$name.xml');
      double attr(String name, int index) => double.parse(
        RegExp('android:$name="([0-9.]+)"')
            .allMatches(xml)
            .elementAt(index)[1]!,
      );
      for (final (i, (start, end, _)) in ZunoMarkPainter.segments.indexed) {
        expect(attr('trimPathStart', i), start, reason: 'start $i');
        expect(attr('trimPathEnd', i), end, reason: 'end $i');
      }
    });
  }

  test('foreground colors match the in-app Zuno mark', () {
    final xml = _read('$_res/drawable/ic_launcher_foreground.xml');
    final colors = RegExp('android:strokeColor="#([0-9A-F]{6})"')
        .allMatches(xml)
        .map((m) => int.parse('FF${m[1]}', radix: 16));
    expect(colors, ZunoMarkPainter.segments.map((s) => s.$3.toARGB32()));
  });

  test('legacy PNG icons are RGBA (transparent around the rounded square)', () {
    final b = File('$_res/mipmap-xxxhdpi/ic_launcher.png').readAsBytesSync();
    expect(b[25], 6); // тип цвета 6 = RGBA
    final png = PngPixels.read('$_res/mipmap-xxxhdpi/ic_launcher.png');
    expect(png.argb(0, 0) >> 24, 0); // угол прозрачный
    expect(png.argb(96, 96), 0xFFF3F5F6); // центр — фон
    expect(png.argb(150, 96), 0xFF2F6FD6); // справа — синяя доля
  });

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
