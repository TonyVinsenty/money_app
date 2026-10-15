import 'dart:io';
import 'dart:typed_data';

/// Пиксели PNG без пакетов: 8 бит на канал, RGB или RGBA, без чересстрочности.
/// Для сторожей иконок: проверить цвет в точке картинки.
final class PngPixels {
  PngPixels._(this.width, this.height, this.channels, this._data);

  factory PngPixels.read(String path) {
    final bytes = File(path).readAsBytesSync();
    final view = ByteData.sublistView(bytes);
    var offset = 8;
    late int width, height, channels;
    final idat = BytesBuilder();
    while (offset < bytes.length) {
      final length = view.getUint32(offset);
      final type = String.fromCharCodes(bytes.sublist(offset + 4, offset + 8));
      final body = bytes.sublist(offset + 8, offset + 8 + length);
      if (type == 'IHDR') {
        final header = ByteData.sublistView(body);
        width = header.getUint32(0);
        height = header.getUint32(4);
        if (body[8] != 8 || body[12] != 0) {
          throw UnsupportedError('нужны 8 бит и без чересстрочности');
        }
        channels = switch (body[9]) {
          2 => 3,
          6 => 4,
          _ => throw UnsupportedError('тип цвета ${body[9]}'),
        };
      } else if (type == 'IDAT') {
        idat.add(body);
      }
      offset += 12 + length;
    }
    final raw = ZLibDecoder().convert(idat.takeBytes());
    final stride = width * channels;
    final data = Uint8List(height * stride);
    for (var y = 0; y < height; y++) {
      final filter = raw[y * (stride + 1)];
      for (var x = 0; x < stride; x++) {
        final value = raw[y * (stride + 1) + 1 + x];
        final left = x >= channels ? data[y * stride + x - channels] : 0;
        final up = y > 0 ? data[(y - 1) * stride + x] : 0;
        final upLeft = x >= channels && y > 0
            ? data[(y - 1) * stride + x - channels]
            : 0;
        final predictor = switch (filter) {
          0 => 0,
          1 => left,
          2 => up,
          3 => (left + up) ~/ 2,
          4 => _paeth(left, up, upLeft),
          _ => throw UnsupportedError('фильтр $filter'),
        };
        data[y * stride + x] = (value + predictor) & 0xFF;
      }
    }
    return PngPixels._(width, height, channels, data);
  }

  final int width;
  final int height;

  /// 3 — RGB, 4 — RGBA.
  final int channels;
  final Uint8List _data;

  /// Цвет точки как 0xAARRGGBB (у RGB альфа — 0xFF).
  int argb(int x, int y) {
    final i = (y * width + x) * channels;
    final a = channels == 4 ? _data[i + 3] : 0xFF;
    return (a << 24) | (_data[i] << 16) | (_data[i + 1] << 8) | _data[i + 2];
  }
}

int _paeth(int a, int b, int c) {
  final p = a + b - c;
  final pa = (p - a).abs();
  final pb = (p - b).abs();
  final pc = (p - c).abs();
  if (pa <= pb && pa <= pc) return a;
  return pb <= pc ? b : c;
}
