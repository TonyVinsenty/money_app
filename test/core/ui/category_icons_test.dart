import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/category_icons.dart';
import 'package:money_app/features/categories/domain/default_categories.dart';
import 'package:money_app/features/csv_import/domain/plan_csv_import.dart';

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

  test('набор около 80 иконок, ключи без повторов и в snake_case', () {
    expect(categoryIconKeys.length, inInclusiveRange(75, 90));
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
    expect(categoryIconKeys.first, 'shopping_cart');
    expect(categoryIconKeys, containsAll(expected.keys));
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

  test('группы идут в утверждённом порядке и непусты', () {
    expect(
      [for (final g in categoryIconGroups) g.title],
      [
        'Покупки и еда',
        'Дом и связь',
        'Транспорт и поездки',
        'Здоровье и красота',
        'Отдых и хобби',
        'Деньги и работа',
        'Семья и разное',
      ],
    );
    for (final group in categoryIconGroups) {
      expect(group.keys, isNotEmpty, reason: group.title);
    }
    expect(categoryIconGroups.first.keys.first, 'shopping_cart');
  });

  test('каждый ключ состоит ровно в одной группе', () {
    final all = [for (final g in categoryIconGroups) ...g.keys];
    expect(all.length, categoryIconKeys.length);
    expect(all.toSet().length, all.length);
    expect(all, categoryIconKeys);
  });

  test('новые значки: ключи, названия и группы из списка пользователя', () {
    const expected = <String, String>{
      'fastfood': 'Фастфуд',
      'storefront': 'Магазин',
      'key': 'Ключ',
      'computer': 'Компьютер',
      'local_taxi': 'Такси',
      'beach_access': 'Пляж',
      'favorite': 'Сердце',
      'self_improvement': 'Йога',
      'music_note': 'Музыка',
      'subscriptions': 'Подписки',
      'credit_card': 'Кредитка',
      'volunteer_activism': 'Благотворительность',
      'family_restroom': 'Семья',
      'star': 'Звезда',
    };
    expected.forEach((key, name) {
      expect(categoryIconName(key), name);
      expect(categoryIconFor(key), isNot(fallbackCategoryIcon), reason: key);
    });
    final group = {
      for (final g in categoryIconGroups)
        for (final k in g.keys) k: g.title,
    };
    expect(group['fastfood'], 'Покупки и еда');
    expect(group['bolt'], 'Дом и связь');
    expect(group['hotel'], 'Транспорт и поездки');
    expect(group['pool'], 'Здоровье и красота');
    expect(group['palette'], 'Отдых и хобби');
    expect(group['percent'], 'Деньги и работа');
    expect(group['gavel'], 'Семья и разное');
    expect(group['more_horiz'], 'Семья и разное');
  });

  test('ключ импорта CSV известен', () {
    expect(isKnownCategoryIconKey(csvImportCategoryIconKey), isTrue);
  });
}
