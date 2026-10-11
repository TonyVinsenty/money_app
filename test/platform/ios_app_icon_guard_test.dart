// Сторож иконки iOS (шаг 7.3, ADR 0013): одна картинка 1024x1024 без альфа-канала.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

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
