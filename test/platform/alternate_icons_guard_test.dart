// Сторож картинок выбора иконки (шаг 8.36, ADR 0014): у каждого варианта есть
// адаптивный значок Android со всеми тремя слоями, PNG для старых Android,
// набор iOS 1024 без альфы и превью 192 px для листа выбора.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/png_pixels.dart';

const _res = 'android/app/src/main/res';
const _ios = 'ios/Runner/Assets.xcassets';

/// id → имя набора iOS и имя ресурсов Android (ADR 0014, п. 3–4).
const _alternates = {
  'ring_blue': ('AppIcon-RingBlue', 'ic_launcher_ring_blue'),
  'coins': ('AppIcon-Coins', 'ic_launcher_coins'),
  'wallet': ('AppIcon-Wallet', 'ic_launcher_wallet'),
};

const _legacySizes = {
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

/// Ссылка `@drawable/имя` или `@color/имя` из слоя адаптивного значка.
String _layer(String xml, String tag) {
  final match = RegExp('<$tag android:drawable="@(drawable|color)/([a-z_]+)"')
      .firstMatch(xml);
  expect(match, isNotNull, reason: tag);
  return '${match![1]}/${match[2]}';
}

void main() {
  _alternates.forEach((id, names) {
    final (iosSet, android) = names;

    test('$id: adaptive icon with background, foreground and monochrome', () {
      final xml = File('$_res/mipmap-anydpi-v26/$android.xml')
          .readAsStringSync();
      expect(xml, contains('<adaptive-icon'));
      for (final tag in ['background', 'foreground', 'monochrome']) {
        final layer = _layer(xml, tag);
        if (layer.startsWith('color/')) {
          expect(layer, 'color/ic_launcher_background', reason: tag);
        } else {
          final file = File('$_res/$layer.xml');
          expect(file.existsSync(), isTrue, reason: '$tag: $layer');
          expect(file.readAsStringSync(), contains('<vector'), reason: layer);
        }
      }
    });

    test('$id: legacy PNG icons with expected sizes', () {
      _legacySizes.forEach((density, px) {
        final png = PngPixels.read('$_res/mipmap-$density/$android.png');
        expect([png.width, png.height], [px, px], reason: density);
        expect(png.channels, 4, reason: density);
        expect(png.argb(0, 0) >> 24, 0, reason: '$density: угол прозрачный');
      });
    });

    test('$id: iOS set $iosSet has one 1024 RGB picture', () {
      final dir = '$_ios/$iosSet.appiconset';
      final json = jsonDecode(
        File('$dir/Contents.json').readAsStringSync(),
      ) as Map<String, dynamic>;
      final images = json['images'] as List<dynamic>;
      expect(images, hasLength(1));
      final entry = images.single as Map<String, dynamic>;
      expect(entry['size'], '1024x1024');
      expect(entry['idiom'], 'universal');
      final png = PngPixels.read('$dir/${entry['filename']}');
      expect([png.width, png.height], [1024, 1024]);
      expect(png.channels, 3); // без альфы
    });
  });

  for (final id in ['ring', ..._alternates.keys]) {
    test('$id: preview 192 px for the picker sheet', () {
      final png = PngPixels.read('assets/app_icons/$id.png');
      expect([png.width, png.height], [192, 192]);
      expect(png.channels, 4);
      expect(png.argb(0, 0) >> 24, 0); // угол скруглён
      expect(png.argb(96, 2) >> 24, 0xFF); // край по центру — рисунок
    });
  }

  test('previews are listed in pubspec.yaml', () {
    expect(
      File('pubspec.yaml').readAsStringSync(),
      contains('    - assets/app_icons/'),
    );
  });

  test('ring blue background is a vertical gradient', () {
    final xml = File('$_res/drawable/ic_launcher_ring_blue_background.xml')
        .readAsStringSync();
    expect(xml, contains('<gradient'));
    expect(xml, contains('#3D7FE6'));
    expect(xml, contains('#2459B8'));
  });
}
