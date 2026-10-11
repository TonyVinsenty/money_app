import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/avatar_glyph.dart';

void main() {
  const other = 'more_horiz';

  test('«кафе» -> «К»', () => expect(avatarGlyph(other, 'кафе'), 'К'));

  test('пробелы по краям обрезаются, «ёлка» -> «Ё»', () {
    expect(avatarGlyph(other, '  ёлка'), 'Ё');
  });

  test('«Прочее» в любом регистре - значок (null)', () {
    expect(avatarGlyph(other, 'Прочее'), isNull);
    expect(avatarGlyph(other, 'прочее'), isNull);
    expect(avatarGlyph(other, ' ПРОЧЕЕ '), isNull);
  });

  test('эмодзи и цифра рисуются как есть', () {
    expect(avatarGlyph(other, '\u{1F600} смех'), '\u{1F600}');
    expect(avatarGlyph(other, '5 звёзд'), '5');
  });

  test('пустое и пробельное имя, null - значок', () {
    expect(avatarGlyph(other, ''), isNull);
    expect(avatarGlyph(other, '   '), isNull);
    expect(avatarGlyph(other, null), isNull);
  });

  test('другой ключ или null - значок', () {
    expect(avatarGlyph('shopping_cart', 'кафе'), isNull);
    expect(avatarGlyph(null, 'кафе'), isNull);
  });
}
