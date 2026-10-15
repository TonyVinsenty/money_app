// Рисует PNG иконок приложения (этап 8, ADR 0014) без пакетов: фигуры из
// SVG раздела 9 `docs/design-review-stage8.md` на поле 1024, сглаживание —
// 4 × 4 пробы на пиксель, PNG собирается вручную (zlib из `dart:io`).
//
// Запуск из корня репозитория: `dart run tool/make_app_icons.dart`.
// Пишет картинки iOS (1024, без альфы) и PNG для старых Android (48–192 px,
// скруглённый квадрат на прозрачном фоне). Векторные слои Android
// (`ic_launcher_foreground.xml`) правятся руками — этот файл их не трогает.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

/// Цвет с прозрачностью, каналы 0..1.
class Rgba {
  const Rgba(this.r, this.g, this.b, [this.a = 1]);

  factory Rgba.hex(int rgb, [double a = 1]) => Rgba(
    ((rgb >> 16) & 0xFF) / 255,
    ((rgb >> 8) & 0xFF) / 255,
    (rgb & 0xFF) / 255,
    a,
  );

  final double r;
  final double g;
  final double b;
  final double a;

  /// Этот цвет поверх [under] (обычное наложение).
  Rgba over(Rgba under) {
    final outA = a + under.a * (1 - a);
    if (outA == 0) return const Rgba(0, 0, 0, 0);
    double mix(double top, double bottom) =>
        (top * a + bottom * under.a * (1 - a)) / outA;
    return Rgba(mix(r, under.r), mix(g, under.g), mix(b, under.b), outA);
  }
}

/// Фигура на поле 1024: цвет в точке или `null`, если точка снаружи.
abstract class Shape {
  const Shape();

  Rgba? colorAt(double x, double y);
}

/// Заливка всего поля, по желанию — вертикальный градиент сверху вниз.
class Background extends Shape {
  const Background(this.top, [Rgba? bottom]) : bottom = bottom ?? top;

  final Rgba top;
  final Rgba bottom;

  @override
  Rgba colorAt(double x, double y) {
    final t = (y / 1024).clamp(0.0, 1.0);
    double lerp(double a, double b) => a + (b - a) * t;
    return Rgba(
      lerp(top.r, bottom.r),
      lerp(top.g, bottom.g),
      lerp(top.b, bottom.b),
      lerp(top.a, bottom.a),
    );
  }
}

/// Дуга-штрих с плоскими концами: доли окружности от верха по часовой.
class Arc extends Shape {
  const Arc(this.radius, this.width, this.start, this.end, this.color);

  final double radius;
  final double width;
  final double start;
  final double end;
  final Rgba color;

  @override
  Rgba? colorAt(double x, double y) {
    final dx = x - 512;
    final dy = y - 512;
    final distance = math.sqrt(dx * dx + dy * dy);
    if ((distance - radius).abs() > width / 2) return null;
    var turn = math.atan2(dx, -dy) / (2 * math.pi);
    if (turn < 0) turn += 1;
    return turn >= start && turn <= end ? color : null;
  }
}

/// Круг; с [width] — кольцо-штрих по окружности радиуса [radius].
class Circle extends Shape {
  const Circle(this.cx, this.cy, this.radius, this.color, {this.width});

  final double cx;
  final double cy;
  final double radius;
  final Rgba color;
  final double? width;

  @override
  Rgba? colorAt(double x, double y) {
    final distance = math.sqrt(math.pow(x - cx, 2) + math.pow(y - cy, 2));
    final width = this.width;
    if (width == null) return distance <= radius ? color : null;
    return (distance - radius).abs() <= width / 2 ? color : null;
  }
}

/// Скруглённый прямоугольник, по желанию повёрнутый на [degrees] вокруг
/// точки ([px], [py]) — как `transform="rotate(deg px py)"` в SVG.
class RoundRect extends Shape {
  const RoundRect(
    this.x,
    this.y,
    this.w,
    this.h,
    this.rx,
    this.color, {
    this.degrees = 0,
    this.px = 0,
    this.py = 0,
  });

  final double x;
  final double y;
  final double w;
  final double h;
  final double rx;
  final Rgba color;
  final double degrees;
  final double px;
  final double py;

  @override
  Rgba? colorAt(double sx, double sy) {
    // Точку поворачиваем обратно — и проверяем неповёрнутый прямоугольник.
    final angle = -degrees * math.pi / 180;
    final dx = sx - px;
    final dy = sy - py;
    final ux = px + dx * math.cos(angle) - dy * math.sin(angle);
    final uy = py + dx * math.sin(angle) + dy * math.cos(angle);
    return insideRoundRect(ux, uy, x, y, w, h, rx) ? color : null;
  }
}

bool insideRoundRect(
  double px,
  double py,
  double x,
  double y,
  double w,
  double h,
  double r,
) {
  if (px < x || py < y || px > x + w || py > y + h) return false;
  final cx = px.clamp(x + r, x + w - r);
  final cy = py.clamp(y + r, y + h - r);
  return math.pow(px - cx, 2) + math.pow(py - cy, 2) <= r * r;
}

/// Иконка: фигуры снизу вверх на поле 1024.
typedef Art = List<Shape>;

Rgba _sample(Art art, double x, double y) {
  var color = const Rgba(0, 0, 0, 0);
  for (final shape in art) {
    final c = shape.colorAt(x, y);
    if (c != null) color = c.over(color);
  }
  return color;
}

const _samples = 4;

/// Рисует картинку [size] × [size]: [map] переводит точку картинки в точку
/// поля 1024 (или `null` — точка прозрачная).
Uint8List _render(
  Art art,
  int size,
  (double, double)? Function(double x, double y) map,
) {
  final pixels = Uint8List(size * size * 4);
  for (var py = 0; py < size; py++) {
    for (var px = 0; px < size; px++) {
      var r = 0.0, g = 0.0, b = 0.0, a = 0.0;
      for (var sy = 0; sy < _samples; sy++) {
        for (var sx = 0; sx < _samples; sx++) {
          final point = map(
            px + (sx + 0.5) / _samples,
            py + (sy + 0.5) / _samples,
          );
          if (point == null) continue;
          final c = _sample(art, point.$1, point.$2);
          // Складываем с учётом прозрачности, чтобы края не темнели.
          r += c.r * c.a;
          g += c.g * c.a;
          b += c.b * c.a;
          a += c.a;
        }
      }
      final i = (py * size + px) * 4;
      const n = _samples * _samples;
      if (a > 0) {
        pixels[i] = (r / a * 255).round();
        pixels[i + 1] = (g / a * 255).round();
        pixels[i + 2] = (b / a * 255).round();
      }
      pixels[i + 3] = (a / n * 255).round();
    }
  }
  return pixels;
}

/// Картинка iOS: поле 1024 целиком, без альфы (скругляет система).
Uint8List renderIos(Art art) =>
    encodePng(_render(art, 1024, (x, y) => (x, y)), 1024, alpha: false);

/// Поле старой иконки Android: отступ и радиус скруглённого квадрата в долях
/// размера (как у иконки этапа 7), увеличение рисунка: безопасный круг 640
/// занимает 80 % квадрата.
const _legacyMargin = 0.039;
const _legacyRadius = 0.219;
const _legacyZoom = 0.8 * 1024 / 640;

/// PNG для старых Android: скруглённый квадрат на прозрачном фоне.
Uint8List renderLegacy(Art art, int size) {
  final margin = size * _legacyMargin;
  final side = size - 2 * margin;
  final radius = size * _legacyRadius;
  final pixels = _render(art, size, (x, y) {
    if (!insideRoundRect(x, y, margin, margin, side, side, radius)) {
      return null;
    }
    final scale = 1024 / side / _legacyZoom;
    return (512 + (x - size / 2) * scale, 512 + (y - size / 2) * scale);
  });
  return encodePng(pixels, size, alpha: true);
}

/// Превью для листа выбора: круг на прозрачном фоне (как в листе Android).
Uint8List renderPreview(Art art, int size) {
  final pixels = _render(art, size, (x, y) {
    final r = size / 2;
    if (math.pow(x - r, 2) + math.pow(y - r, 2) > r * r) return null;
    final scale = 1024 / size;
    return (x * scale, y * scale);
  });
  return encodePng(pixels, size, alpha: true);
}

Uint8List encodePng(Uint8List rgba, int size, {required bool alpha}) {
  final channels = alpha ? 4 : 3;
  final raw = BytesBuilder();
  for (var y = 0; y < size; y++) {
    raw.addByte(0); // фильтр строки: нет
    for (var x = 0; x < size; x++) {
      final i = (y * size + x) * 4;
      raw.add(rgba.sublist(i, i + channels));
    }
  }
  final header = ByteData(13)
    ..setUint32(0, size)
    ..setUint32(4, size)
    ..setUint8(8, 8)
    ..setUint8(9, alpha ? 6 : 2);
  final out = BytesBuilder()
    ..add([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    ..add(_chunk('IHDR', header.buffer.asUint8List()))
    ..add(_chunk('IDAT', ZLibCodec(level: 9).encode(raw.takeBytes())))
    ..add(_chunk('IEND', const []));
  return out.takeBytes();
}

List<int> _chunk(String type, List<int> data) {
  final body = [...type.codeUnits, ...data];
  final length = ByteData(4)..setUint32(0, data.length);
  final crc = ByteData(4)..setUint32(0, _crc32(body));
  return [...length.buffer.asUint8List(), ...body, ...crc.buffer.asUint8List()];
}

final List<int> _crcTable = List.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return crc ^ 0xFFFFFFFF;
}

// Иконки (раздел 9 отчёта). Доли кольца — как в `ic_launcher_foreground.xml`
// и `ZunoMarkPainter`: 0–0,425 / 0,455–0,725 / 0,755–0,97.

final _light = Rgba.hex(0xF3F5F6);

Art ring({required Background background, required List<int> colors}) => [
  background,
  Arc(250, 120, 0, 0.425, Rgba.hex(colors[0])),
  Arc(250, 120, 0.455, 0.725, Rgba.hex(colors[1])),
  Arc(250, 120, 0.755, 0.97, Rgba.hex(colors[2])),
];

/// Вариант 1 «Кольцо крупнее» — иконка по умолчанию (шаг 8.35).
final Art iconRing = ring(
  background: Background(_light),
  colors: const [0x2F6FD6, 0xE9823A, 0x7B57C9],
);

const _iosDir = 'ios/Runner/Assets.xcassets';
const _res = 'android/app/src/main/res';
const _legacySizes = {
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

void _write(String path, Uint8List bytes) {
  File(path).writeAsBytesSync(bytes);
  stdout.writeln('$path (${bytes.length} байт)');
}

void main() {
  _write(
    '$_iosDir/AppIcon.appiconset/Icon-App-1024x1024@1x.png',
    renderIos(iconRing),
  );
  _legacySizes.forEach((density, size) {
    _write(
      '$_res/mipmap-$density/ic_launcher.png',
      renderLegacy(iconRing, size),
    );
  });
}
