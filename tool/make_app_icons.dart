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

/// Превью для листа выбора (ADR 0014, п. 5): весь рисунок в скруглённом
/// квадрате, как иконка на iPhone; снаружи прозрачно.
Uint8List renderPreview(Art art, int size) {
  final radius = size * 0.2237;
  final s = size.toDouble();
  final pixels = _render(art, size, (x, y) {
    if (!insideRoundRect(x, y, 0, 0, s, s, radius)) return null;
    return (x * 1024 / size, y * 1024 / size);
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

const _lightHex = 0xF3F5F6;
final _light = Rgba.hex(_lightHex);
const _ringColors = [0x2F6FD6, 0xE9823A, 0x7B57C9];
const _ringBlueColors = [0xFFFFFF, 0xFFB36B, 0xC9B6FF];
const _blueTop = 0x3D7FE6;
const _blueBottom = 0x2459B8;
const _trims = [(0.0, 0.425), (0.455, 0.725), (0.755, 0.97)];

Art ring({required Background background, required List<int> colors}) => [
  background,
  for (final (i, (start, end)) in _trims.indexed)
    Arc(250, 120, start, end, Rgba.hex(colors[i])),
];

/// Вариант 1 «Кольцо крупнее» — иконка по умолчанию (шаг 8.35).
final Art iconRing = ring(background: Background(_light), colors: _ringColors);

/// Вариант 2 «Кольцо на синем».
final Art iconRingBlue = ring(
  background: Background(Rgba.hex(_blueTop), Rgba.hex(_blueBottom)),
  colors: _ringBlueColors,
);

/// Монета варианта 6: центр, радиус по SVG (середина светлой обводки
/// шириной 20), цвет и радиус блика (белая обводка 16, прозрачность 0,45).
typedef Coin = (double cx, double cy, double r, int color, double glint);

/// Снизу вверх: оранжевая, фиолетовая, синяя (передняя).
const _coins = <Coin>[
  (642, 412, 150, 0xE9823A, 114),
  (682, 622, 100, 0x7B57C9, 68),
  (432, 562, 200, 0x2F6FD6, 160),
];

/// Вариант 6 «Монеты». Блик каждой монеты рисуется сразу после неё (в SVG
/// отчёта — после всех монет, и блик задней ложился поверх передней).
final Art iconCoins = [
  Background(_light),
  for (final (cx, cy, r, color, glint) in _coins) ...[
    Circle(cx, cy, r + 10, _light),
    Circle(cx, cy, r - 10, Rgba.hex(color)),
    Circle(cx, cy, glint, Rgba.hex(0xFFFFFF, 0.45), width: 16),
  ],
];

/// Прямоугольник варианта 7: x, y, ширина, высота, скругление, цвет и
/// поворот (градусы, точка поворота).
typedef Slab = (
  double x,
  double y,
  double w,
  double h,
  double rx,
  int color,
  double degrees,
  double px,
  double py,
);

const _walletCards = <Slab>[
  (330, 236, 360, 170, 28, 0x7B57C9, 8, 510, 321),
  (280, 262, 360, 160, 28, 0xE9823A, -6, 460, 342),
];
const Slab _walletBody = (222, 332, 580, 380, 72, 0x2F6FD6, 0, 0, 0);
const Slab _walletClasp = (592, 452, 210, 140, 44, _blueBottom, 0, 0, 0);
const _walletDot = (660.0, 522.0, 24.0);

RoundRect _slab(Slab s) => RoundRect(
  s.$1,
  s.$2,
  s.$3,
  s.$4,
  s.$5,
  Rgba.hex(s.$6),
  degrees: s.$7,
  px: s.$8,
  py: s.$9,
);

/// Вариант 7 «Кошелёк».
final Art iconWallet = [
  Background(_light),
  for (final card in _walletCards) _slab(card),
  _slab(_walletBody),
  _slab(_walletClasp),
  Circle(_walletDot.$1, _walletDot.$2, _walletDot.$3, _light),
];

// Векторные слои Android (поле 108 dp). Рисунок 1024 переносится так, чтобы
// безопасный круг 640 стал безопасным кругом 66 dp; у колец — как у варианта 1
// (радиус 26,4, толщина 12,7 — как в плане шага 8.35, а не 12,672 по пропорции).

const _ringScale = 26.4 / 250;
const _artScale = 66 / 640;

String _n(double value) {
  var text = value.toStringAsFixed(3);
  if (text.contains('.')) {
    text = text
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }
  return text == '-0' ? '0' : text;
}

String _hex(int rgb) =>
    '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';

double _x(double v) => 54 + (v - 512) * _artScale;
double _len(double v) => v * _artScale;

const _generated =
    '<!-- Сгенерировано tool/make_app_icons.dart: правьте скрипт, '
    'а не этот файл. -->';

const _vectorHead =
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '$_generated\n'
    '<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
    '    xmlns:aapt="http://schemas.android.com/aapt"\n'
    '    android:width="108dp"\n'
    '    android:height="108dp"\n'
    '    android:viewportWidth="108"\n'
    '    android:viewportHeight="108">\n';
const _vectorTail = '</vector>\n';

String _ringVector(List<int> colors) {
  final r = 250 * _ringScale;
  final top = _n(54 - r);
  final bottom = _n(54 + r);
  final rr = _n(r);
  final buffer = StringBuffer(_vectorHead);
  for (final (i, (start, end)) in _trims.indexed) {
    buffer
      ..writeln('    <path')
      ..writeln(
        '        android:pathData="M54,$top A$rr,$rr 0 1,1 54,$bottom '
        'A$rr,$rr 0 1,1 54,$top"',
      )
      ..writeln('        android:strokeColor="${_hex(colors[i])}"')
      ..writeln('        android:strokeWidth="12.7"')
      ..writeln('        android:strokeLineCap="butt"')
      ..writeln('        android:trimPathStart="${_n(start)}"')
      ..writeln('        android:trimPathEnd="${_n(end)}" />');
  }
  return '$buffer$_vectorTail';
}

String _gradientBackground() {
  final buffer = StringBuffer(_vectorHead)
    ..writeln('    <path android:pathData="M0,0 H108 V108 H0 Z">')
    ..writeln('        <aapt:attr name="android:fillColor">')
    ..writeln('            <gradient')
    ..writeln('                android:type="linear"')
    ..writeln('                android:startX="54"')
    ..writeln('                android:startY="0"')
    ..writeln('                android:endX="54"')
    ..writeln('                android:endY="108">')
    ..writeln(
      '                <item android:offset="0" '
      'android:color="${_hex(_blueTop)}" />',
    )
    ..writeln(
      '                <item android:offset="1" '
      'android:color="${_hex(_blueBottom)}" />',
    )
    ..writeln('            </gradient>')
    ..writeln('        </aapt:attr>')
    ..writeln('    </path>');
  return '$buffer$_vectorTail';
}

/// Круг одной фигурой пути (две полуокружности).
String _circlePath(double cx, double cy, double r) {
  final x = _x(cx), y = _x(cy), rr = _n(_len(r));
  return 'M${_n(x - _len(r))},${_n(y)} '
      'A$rr,$rr 0 1,1 ${_n(x + _len(r))},${_n(y)} '
      'A$rr,$rr 0 1,1 ${_n(x - _len(r))},${_n(y)} Z';
}

String _path(String attributes, String data) =>
    '    <path $attributes\n        android:pathData="$data" />\n';

String _coinsVector() {
  final buffer = StringBuffer(_vectorHead);
  for (final (cx, cy, r, color, glint) in _coins) {
    buffer
      ..write(
        _path(
          'android:fillColor="${_hex(_lightHex)}"',
          _circlePath(cx, cy, r + 10),
        ),
      )
      ..write(
        _path(
          'android:fillColor="${_hex(color)}"',
          _circlePath(cx, cy, r - 10),
        ),
      )
      ..write(
        _path(
          'android:strokeColor="#FFFFFF" android:strokeAlpha="0.45" '
          'android:strokeWidth="${_n(_len(16))}"',
          _circlePath(cx, cy, glint),
        ),
      );
  }
  return '$buffer$_vectorTail';
}

/// Видимые части контура монеты [index] (не закрытые монетами спереди вместе
/// с их светлой обводкой) — дуги для тематического значка.
List<String> _visibleOutline(int index) {
  final (cx, cy, r, _, _) = _coins[index];
  final front = _coins.sublist(index + 1);
  (double, double) point(double degrees) {
    final a = degrees * math.pi / 180;
    return (cx + r * math.cos(a), cy + r * math.sin(a));
  }

  bool visible(double degrees) {
    final (x, y) = point(degrees);
    return front.every(
      (c) =>
          math.pow(x - c.$1, 2) + math.pow(y - c.$2, 2) >
          math.pow(c.$3 + 10, 2),
    );
  }

  const step = 0.25;
  // Начинаем с закрытой точки, чтобы видимая дуга не рвалась на 0°.
  var origin = 0.0;
  while (origin < 360 && visible(origin)) {
    origin += step;
  }
  if (origin >= 360) return [_circlePath(cx, cy, r)];
  final rr = _n(_len(r));
  final arcs = <String>[];
  double? runStart;
  for (var d = 0.0; d <= 360; d += step) {
    final degrees = origin + d;
    final isVisible = d < 360 && visible(degrees);
    if (isVisible) {
      runStart ??= degrees;
    } else if (runStart != null) {
      final end = degrees - step;
      final (x0, y0) = point(runStart);
      final (x1, y1) = point(end);
      final large = end - runStart > 180 ? 1 : 0;
      arcs.add(
        'M${_n(_x(x0))},${_n(_x(y0))} '
        'A$rr,$rr 0 $large,1 ${_n(_x(x1))},${_n(_x(y1))}',
      );
      runStart = null;
    }
  }
  return arcs;
}

String _coinsMonochrome() {
  final buffer = StringBuffer(_vectorHead);
  for (var i = 0; i < _coins.length; i++) {
    for (final arc in _visibleOutline(i)) {
      buffer.write(
        _path(
          'android:strokeColor="#FFFFFF" '
          'android:strokeWidth="${_n(_len(24))}"',
          arc,
        ),
      );
    }
  }
  return '$buffer$_vectorTail';
}

String _roundRectPath(Slab s) {
  final x = _x(s.$1), y = _x(s.$2), w = _len(s.$3), h = _len(s.$4);
  final r = _len(s.$5);
  final a = '${_n(r)},${_n(r)} 0 0,1';
  return 'M${_n(x + r)},${_n(y)} H${_n(x + w - r)} '
      'A$a ${_n(x + w)},${_n(y + r)} V${_n(y + h - r)} '
      'A$a ${_n(x + w - r)},${_n(y + h)} H${_n(x + r)} '
      'A$a ${_n(x)},${_n(y + h - r)} V${_n(y + r)} '
      'A$a ${_n(x + r)},${_n(y)} Z';
}

String _slabPath(Slab s, String paint) {
  final path = _path(paint, _roundRectPath(s));
  if (s.$7 == 0) return path;
  return '    <group android:rotation="${_n(s.$7)}" '
      'android:pivotX="${_n(_x(s.$8))}" android:pivotY="${_n(_x(s.$9))}">\n'
      '$path    </group>\n';
}

String _walletVector() {
  final buffer = StringBuffer(_vectorHead);
  for (final slab in [..._walletCards, _walletBody, _walletClasp]) {
    buffer.write(_slabPath(slab, 'android:fillColor="${_hex(slab.$6)}"'));
  }
  buffer.write(
    _path(
      'android:fillColor="${_hex(_lightHex)}"',
      _circlePath(_walletDot.$1, _walletDot.$2, _walletDot.$3),
    ),
  );
  return '$buffer$_vectorTail';
}

String _walletMonochrome() {
  final buffer = StringBuffer(_vectorHead);
  for (final card in _walletCards) {
    buffer.write(_slabPath(card, 'android:fillColor="#FFFFFF"'));
  }
  // Кошелёк, застёжка и кнопка одним путём «чёт-нечет»: застёжка вырезана,
  // кнопка внутри неё снова закрашена.
  buffer.write(
    _path(
      'android:fillColor="#FFFFFF" android:fillType="evenOdd"',
      '${_roundRectPath(_walletBody)} ${_roundRectPath(_walletClasp)} '
          '${_circlePath(_walletDot.$1, _walletDot.$2, _walletDot.$3)}',
    ),
  );
  return '$buffer$_vectorTail';
}

String _adaptiveIcon({
  required String background,
  required String foreground,
  required String monochrome,
}) =>
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '$_generated\n'
    '<adaptive-icon '
    'xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="$background" />\n'
    '    <foreground android:drawable="$foreground" />\n'
    '    <monochrome android:drawable="$monochrome" />\n'
    '</adaptive-icon>\n';

const _iosDir = 'ios/Runner/Assets.xcassets';
const _res = 'android/app/src/main/res';
const _legacySizes = {
  'mdpi': 48,
  'hdpi': 72,
  'xhdpi': 96,
  'xxhdpi': 144,
  'xxxhdpi': 192,
};

/// Иконка выбора (ADR 0014): `id`, имя набора iOS (`null` — набор по
/// умолчанию `AppIcon`), имя ресурсов Android и рисунок.
typedef IconVariant = (String id, String? iosSet, String android, Art art);

final _variants = <IconVariant>[
  ('ring', null, 'ic_launcher', iconRing),
  ('ring_blue', 'AppIcon-RingBlue', 'ic_launcher_ring_blue', iconRingBlue),
  ('coins', 'AppIcon-Coins', 'ic_launcher_coins', iconCoins),
  ('wallet', 'AppIcon-Wallet', 'ic_launcher_wallet', iconWallet),
];

const _iosContents =
    '{\n'
    '  "images" : [\n'
    '    {\n'
    '      "filename" : "Icon-App-1024x1024@1x.png",\n'
    '      "idiom" : "universal",\n'
    '      "platform" : "ios",\n'
    '      "size" : "1024x1024"\n'
    '    }\n'
    '  ],\n'
    '  "info" : {\n'
    '    "author" : "xcode",\n'
    '    "version" : 1\n'
    '  }\n'
    '}\n';

void _write(String path, Uint8List bytes) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);
  stdout.writeln('$path (${bytes.length} байт)');
}

void _writeText(String path, String text) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(text);
  stdout.writeln(path);
}

void main() {
  for (final (id, iosSet, android, art) in _variants) {
    final set = iosSet ?? 'AppIcon';
    _write(
      '$_iosDir/$set.appiconset/Icon-App-1024x1024@1x.png',
      renderIos(art),
    );
    if (iosSet != null) {
      _writeText('$_iosDir/$set.appiconset/Contents.json', _iosContents);
    }
    _legacySizes.forEach((density, size) {
      _write('$_res/mipmap-$density/$android.png', renderLegacy(art, size));
    });
    _write('assets/app_icons/$id.png', renderPreview(art, 192));
  }

  // Векторные слои: у варианта 1 они лежат под прежними именами
  // (`ic_launcher_foreground`, `ic_launcher_monochrome`).
  const white = [0xFFFFFF, 0xFFFFFF, 0xFFFFFF];
  final drawables = {
    'ic_launcher_foreground': _ringVector(_ringColors),
    'ic_launcher_monochrome': _ringVector(white),
    'ic_launcher_ring_blue_foreground': _ringVector(_ringBlueColors),
    'ic_launcher_ring_blue_background': _gradientBackground(),
    'ic_launcher_coins_foreground': _coinsVector(),
    'ic_launcher_coins_monochrome': _coinsMonochrome(),
    'ic_launcher_wallet_foreground': _walletVector(),
    'ic_launcher_wallet_monochrome': _walletMonochrome(),
  };
  drawables.forEach((name, xml) {
    _writeText('$_res/drawable/$name.xml', xml);
  });
  _writeText(
    '$_res/mipmap-anydpi-v26/ic_launcher_ring_blue.xml',
    _adaptiveIcon(
      background: '@drawable/ic_launcher_ring_blue_background',
      foreground: '@drawable/ic_launcher_ring_blue_foreground',
      monochrome: '@drawable/ic_launcher_monochrome',
    ),
  );
  for (final id in ['coins', 'wallet']) {
    _writeText(
      '$_res/mipmap-anydpi-v26/ic_launcher_$id.xml',
      _adaptiveIcon(
        background: '@color/ic_launcher_background',
        foreground: '@drawable/ic_launcher_${id}_foreground',
        monochrome: '@drawable/ic_launcher_${id}_monochrome',
      ),
    );
  }
}
