// Сторож иконки iOS (шаг 7.3, ADR 0013): одна картинка 1024x1024 без альфа-канала.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../support/png_pixels.dart';

const _dir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
const _name = 'Icon-App-1024x1024@1x.png';

void main() {
  test('Contents.json has exactly one universal 1024 entry', () {
    final json = jsonDecode(
      File('$_dir/Contents.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final images = json['images'] as List<dynamic>;
    expect(images, hasLength(1));
    final entry = images.single as Map<String, dynamic>;
    expect(entry['filename'], _name);
    expect(entry['idiom'], 'universal');
    expect(entry['platform'], 'ios');
    expect(entry['size'], '1024x1024');
  });

  test('icon PNG is 1024x1024 RGB without alpha', () {
    final file = File('$_dir/$_name');
    expect(file.existsSync(), isTrue);
    final bytes = file.readAsBytesSync();
    final data = ByteData.sublistView(bytes);
    expect(data.getUint32(16), 1024); // ширина в IHDR
    expect(data.getUint32(20), 1024); // высота в IHDR
    expect(bytes[24], 8); // глубина цвета
    expect(bytes[25], 2); // тип цвета 2 = RGB, 6 = с альфой
  });

  // Шаг 8.35: вариант 1 «Кольцо крупнее» — кольцо радиуса 250 и толщины 120
  // (у прежнего знака радиус 167: в этих точках был фон).
  test('icon is variant 1: big ring with blue, orange and purple parts', () {
    final png = PngPixels.read('$_dir/$_name');
    expect(png.argb(512, 512), 0xFFF3F5F6); // центр — фон
    expect(png.argb(10, 10), 0xFFF3F5F6); // угол — фон, без прозрачности
    expect(png.argb(762, 512), 0xFF2F6FD6); // справа — синяя доля
    expect(png.argb(400, 735), 0xFFE9823A); // слева снизу — оранжевая
    expect(png.argb(330, 330), 0xFF7B57C9); // слева сверху — фиолетовая
    expect(png.argb(512, 220), 0xFF2F6FD6); // верх кольца радиуса 250
  });

  test('no other PNG files in the icon set', () {
    final pngs = Directory(_dir)
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.toLowerCase().endsWith('.png'))
        .toList();
    expect(pngs, [_name]);
  });
}
