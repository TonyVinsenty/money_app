import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/category_icons.dart';
import 'package:money_app/features/categories/domain/default_categories.dart';

void main() {
  test('все ключи иконок из набора по умолчанию входят в набор для выбора', () {
    for (final category in defaultCategories) {
      expect(
        isKnownCategoryIconKey(category.iconKey),
        isTrue,
        reason: 'нет иконки для "${category.iconKey}" (${category.name})',
      );
      expect(categoryIconKeys, contains(category.iconKey));
      expect(categoryIconFor(category.iconKey), isNot(fallbackCategoryIcon));
    }
  });

  test('набор около 30 иконок, ключи без повторов и в snake_case', () {
    expect(categoryIconKeys.length, inInclusiveRange(28, 32));
    expect(categoryIconKeys.toSet().length, categoryIconKeys.length);
    for (final key in categoryIconKeys) {
      expect(key, matches(RegExp(r'^[a-z][a-z0-9]*(_[a-z0-9]+)*$')));
    }
  });

  test('каждый ключ набора находится и не даёт запасную иконку', () {
    for (final key in categoryIconKeys) {
      expect(isKnownCategoryIconKey(key), isTrue, reason: key);
      expect(categoryIconFor(key), isNot(fallbackCategoryIcon), reason: key);
    }
  });

  test('у каждой иконки есть название, названия не повторяются', () {
    final names = [for (final key in categoryIconKeys) categoryIconName(key)];
    for (final name in names) {
      expect(name.trim(), isNotEmpty);
      expect(name, isNot(fallbackCategoryIconName));
    }
    expect(names.toSet().length, names.length);
  });

  test('утверждённые названия иконок, у которых название было неточным', () {
    expect(categoryIconName('more_horiz'), 'Другое');
    expect(categoryIconName('card_giftcard'), 'Карта');
    expect(categoryIconName('shopping_bag'), 'Сумка');
    expect(categoryIconName('build'), 'Инструменты');
    expect(categoryIconName('trending_up'), 'График');
  });

  test('список ключей нельзя изменить', () {
    expect(() => categoryIconKeys.add('x'), throwsUnsupportedError);
  });

  test('прежние 30 ключей и их названия не изменились', () {
    const expected = <String, String>{
      'shopping_cart': 'Корзина',
      'restaurant': 'Ресторан',
      'directions_bus': 'Автобус',
      'house': 'Дом',
      'medical_services': 'Медицина',
      'checkroom': 'Одежда',
      'sports_esports': 'Игры',
      'phone_android': 'Телефон',
      'card_giftcard': 'Карта',
      'more_horiz': 'Другое',
      'payments': 'Деньги',
      'work': 'Работа',
      'redeem': 'Подарок',
      'local_cafe': 'Кофе',
      'local_gas_station': 'Заправка',
      'directions_car': 'Машина',
      'flight': 'Самолёт',
      'school': 'Учёба',
      'fitness_center': 'Спорт',
      'pets': 'Питомцы',
      'child_care': 'Дети',
      'movie': 'Кино',
      'savings': 'Копилка',
      'account_balance': 'Банк',
      'trending_up': 'График',
      'wifi': 'Интернет',
      'build': 'Инструменты',
      'spa': 'Красота',
      'local_pharmacy': 'Аптека',
      'shopping_bag': 'Сумка',
    };
    expect(categoryIconKeys, expected.keys.toList());
    expected.forEach((key, name) => expect(categoryIconName(key), name));
  });

  test('символы не попадают в список ключей для сетки выбора', () {
    expect(categoryIconKeys.where((k) => k.startsWith('glyph:')), isEmpty);
  });

  test('русские буквы (33, с Ё), латинские (26) и цифры известны', () {
    final ru = [
      for (var c = 0x410; c <= 0x42F; c++) String.fromCharCode(c),
      String.fromCharCode(0x401),
    ];
    expect(ru.length, 33);
    for (final ch in ru) {
      expect(isKnownCategoryIconKey('glyph:$ch'), isTrue, reason: ch);
      expect(categoryGlyphFor('glyph:$ch'), ch);
      expect(categoryIconName('glyph:$ch'), 'Буква $ch');
    }
    for (var c = 0x41; c <= 0x5A; c++) {
      final ch = String.fromCharCode(c);
      expect(isKnownCategoryIconKey('glyph:$ch'), isTrue, reason: ch);
      expect(categoryIconName('glyph:$ch'), 'Латинская буква $ch');
    }
    for (var d = 0; d <= 9; d++) {
      expect(isKnownCategoryIconKey('glyph:$d'), isTrue);
      expect(categoryIconName('glyph:$d'), 'Цифра $d');
    }
  });

  test('конкретные примеры названий символов', () {
    expect(categoryIconName('glyph:Ж'), 'Буква Ж');
    expect(categoryIconName('glyph:Ё'), 'Буква Ё');
    expect(categoryIconName('glyph:D'), 'Латинская буква D');
    expect(categoryIconName('glyph:A'), 'Латинская буква A');
    expect(categoryIconName('glyph:0'), 'Цифра 0');
    expect(categoryIconName('glyph:9'), 'Цифра 9');
  });

  test('неверные символьные ключи неизвестны', () {
    for (final key in [
      'glyph:ж',
      'glyph:d',
      'glyph:ЖЖ',
      'glyph:',
      'glyph:Ω',
      'glyph:10',
      'glyph: ',
      'Glyph:Ж',
    ]) {
      expect(isKnownCategoryIconKey(key), isFalse, reason: key);
      expect(categoryGlyphFor(key), isNull, reason: key);
      expect(categoryIconName(key), fallbackCategoryIconName, reason: key);
      expect(categoryIconFor(key), fallbackCategoryIcon, reason: key);
    }
  });

  test('неизвестный ключ даёт запасную иконку и название', () {
    expect(isKnownCategoryIconKey('no_such_icon'), isFalse);
    expect(categoryIconFor('no_such_icon'), fallbackCategoryIcon);
    expect(categoryIconFor(''), fallbackCategoryIcon);
    expect(categoryIconName('no_such_icon'), fallbackCategoryIconName);
  });
}
