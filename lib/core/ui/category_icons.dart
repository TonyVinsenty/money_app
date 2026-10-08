import 'package:flutter/material.dart';

/// Иконка на случай, если ключ неизвестен (например, его сохранила будущая
/// версия приложения). Категория при этом остаётся видимой и нажимаемой.
const IconData fallbackCategoryIcon = Icons.category_outlined;

/// Название иконки, если ключ неизвестен.
const String fallbackCategoryIconName = 'Категория';

/// Иконка и её русское название (название читает скринридер).
typedef _IconEntry = ({IconData icon, String name});

/// Группа значков в сетке выбора: заголовок и ключи в порядке показа.
typedef CategoryIconGroup = ({String title, List<String> keys});

typedef _IconGroupData = ({String title, Map<String, _IconEntry> icons});

/// Фиксированный набор иконок для категорий по группам: «ключ -> иконка и
/// название».
///
/// В базе хранится только строковый ключ (snake_case), а не код иконки: так
/// иконка не «ломается» в релизной сборке. Порядок групп и записей — порядок в
/// сетке выбора; первая иконка (`shopping_cart`) используется по умолчанию.
/// Ключи 13 категорий по умолчанию и прежних 30 иконок менять нельзя: они уже
/// лежат в базе.
const List<_IconGroupData> _iconGroups = <_IconGroupData>[
  (
    title: 'Покупки и еда',
    icons: <String, _IconEntry>{
      'shopping_cart': (icon: Icons.shopping_cart, name: 'Корзина'),
      'shopping_bag': (icon: Icons.shopping_bag, name: 'Сумка'),
      'checkroom': (icon: Icons.checkroom, name: 'Одежда'),
      'restaurant': (icon: Icons.restaurant, name: 'Ресторан'),
      'local_cafe': (icon: Icons.local_cafe, name: 'Кофе'),
      'fastfood': (icon: Icons.fastfood, name: 'Фастфуд'),
      'local_pizza': (icon: Icons.local_pizza, name: 'Пицца'),
      'bakery_dining': (icon: Icons.bakery_dining, name: 'Выпечка'),
      'cake': (icon: Icons.cake, name: 'Торт'),
      'icecream': (icon: Icons.icecream, name: 'Мороженое'),
      'local_bar': (icon: Icons.local_bar, name: 'Бар'),
      'storefront': (icon: Icons.storefront, name: 'Магазин'),
    },
  ),
  (
    title: 'Дом и связь',
    icons: <String, _IconEntry>{
      'house': (icon: Icons.house, name: 'Дом'),
      'build': (icon: Icons.build, name: 'Инструменты'),
      'phone_android': (icon: Icons.phone_android, name: 'Телефон'),
      'wifi': (icon: Icons.wifi, name: 'Интернет'),
      'key': (icon: Icons.key, name: 'Ключ'),
      'bolt': (icon: Icons.bolt, name: 'Электричество'),
      'water_drop': (icon: Icons.water_drop, name: 'Вода'),
      'lightbulb': (icon: Icons.lightbulb, name: 'Лампа'),
      'chair': (icon: Icons.chair, name: 'Мебель'),
      'cleaning_services': (icon: Icons.cleaning_services, name: 'Уборка'),
      'local_laundry_service': (
        icon: Icons.local_laundry_service,
        name: 'Стирка',
      ),
      'tv': (icon: Icons.tv, name: 'Телевизор'),
      'computer': (icon: Icons.computer, name: 'Компьютер'),
    },
  ),
  (
    title: 'Транспорт и поездки',
    icons: <String, _IconEntry>{
      'directions_bus': (icon: Icons.directions_bus, name: 'Автобус'),
      'directions_car': (icon: Icons.directions_car, name: 'Машина'),
      'local_gas_station': (icon: Icons.local_gas_station, name: 'Заправка'),
      'flight': (icon: Icons.flight, name: 'Самолёт'),
      'local_taxi': (icon: Icons.local_taxi, name: 'Такси'),
      'train': (icon: Icons.train, name: 'Поезд'),
      'subway': (icon: Icons.subway, name: 'Метро'),
      'pedal_bike': (icon: Icons.pedal_bike, name: 'Велосипед'),
      'local_parking': (icon: Icons.local_parking, name: 'Парковка'),
      'hotel': (icon: Icons.hotel, name: 'Отель'),
      'luggage': (icon: Icons.luggage, name: 'Чемодан'),
      'beach_access': (icon: Icons.beach_access, name: 'Пляж'),
    },
  ),
  (
    title: 'Здоровье и красота',
    icons: <String, _IconEntry>{
      'medical_services': (icon: Icons.medical_services, name: 'Медицина'),
      'local_pharmacy': (icon: Icons.local_pharmacy, name: 'Аптека'),
      'fitness_center': (icon: Icons.fitness_center, name: 'Спорт'),
      'spa': (icon: Icons.spa, name: 'Красота'),
      'favorite': (icon: Icons.favorite, name: 'Сердце'),
      'content_cut': (icon: Icons.content_cut, name: 'Стрижка'),
      'sports_soccer': (icon: Icons.sports_soccer, name: 'Футбол'),
      'pool': (icon: Icons.pool, name: 'Бассейн'),
      'self_improvement': (icon: Icons.self_improvement, name: 'Йога'),
    },
  ),
  (
    title: 'Отдых и хобби',
    icons: <String, _IconEntry>{
      'sports_esports': (icon: Icons.sports_esports, name: 'Игры'),
      'movie': (icon: Icons.movie, name: 'Кино'),
      'music_note': (icon: Icons.music_note, name: 'Музыка'),
      'menu_book': (icon: Icons.menu_book, name: 'Книги'),
      'theater_comedy': (icon: Icons.theater_comedy, name: 'Театр'),
      'palette': (icon: Icons.palette, name: 'Рисование'),
      'photo_camera': (icon: Icons.photo_camera, name: 'Фото'),
      'celebration': (icon: Icons.celebration, name: 'Праздник'),
      'park': (icon: Icons.park, name: 'Парк'),
      'subscriptions': (icon: Icons.subscriptions, name: 'Подписки'),
    },
  ),
  (
    title: 'Деньги и работа',
    icons: <String, _IconEntry>{
      'payments': (icon: Icons.payments, name: 'Деньги'),
      'work': (icon: Icons.work, name: 'Работа'),
      'account_balance': (icon: Icons.account_balance, name: 'Банк'),
      'savings': (icon: Icons.savings, name: 'Копилка'),
      'trending_up': (icon: Icons.trending_up, name: 'График'),
      'card_giftcard': (icon: Icons.card_giftcard, name: 'Карта'),
      'credit_card': (icon: Icons.credit_card, name: 'Кредитка'),
      'account_balance_wallet': (
        icon: Icons.account_balance_wallet,
        name: 'Кошелёк',
      ),
      'receipt_long': (icon: Icons.receipt_long, name: 'Чек'),
      'percent': (icon: Icons.percent, name: 'Проценты'),
      'currency_bitcoin': (icon: Icons.currency_bitcoin, name: 'Крипта'),
      'sell': (icon: Icons.sell, name: 'Скидка'),
      'volunteer_activism': (
        icon: Icons.volunteer_activism,
        name: 'Благотворительность',
      ),
    },
  ),
  (
    title: 'Семья и разное',
    icons: <String, _IconEntry>{
      'child_care': (icon: Icons.child_care, name: 'Дети'),
      'pets': (icon: Icons.pets, name: 'Питомцы'),
      'school': (icon: Icons.school, name: 'Учёба'),
      'redeem': (icon: Icons.redeem, name: 'Подарок'),
      'more_horiz': (icon: Icons.more_horiz, name: 'Другое'),
      'family_restroom': (icon: Icons.family_restroom, name: 'Семья'),
      'toys': (icon: Icons.toys, name: 'Игрушки'),
      'local_florist': (icon: Icons.local_florist, name: 'Цветы'),
      'smoking_rooms': (icon: Icons.smoking_rooms, name: 'Сигареты'),
      'gavel': (icon: Icons.gavel, name: 'Штраф'),
      'local_shipping': (icon: Icons.local_shipping, name: 'Доставка'),
      'star': (icon: Icons.star, name: 'Звезда'),
    },
  ),
];

final Map<String, _IconEntry> _categoryIcons =
    Map<String, _IconEntry>.unmodifiable({
      for (final group in _iconGroups) ...group.icons,
    });

/// Ключи иконок Material для выбора, в порядке показа (по группам). Первый —
/// иконка по умолчанию. Символов (`glyph:`) здесь нет: они идут отдельными
/// группами в [categoryIconGroups].
final List<String> categoryIconKeys = List<String>.unmodifiable([
  for (final group in _iconGroups) ...group.icons.keys,
]);

/// Группы значков для сетки выбора, в порядке показа: сначала иконки, в конце
/// прокрутки — русские буквы, латинские буквы и цифры.
final List<CategoryIconGroup> categoryIconGroups =
    List<CategoryIconGroup>.unmodifiable([
      for (final group in _iconGroups)
        (title: group.title, keys: List<String>.unmodifiable(group.icons.keys)),
      (title: 'Русские буквы', keys: _glyphKeys(_russianLetterCodes)),
      (title: 'Латинские буквы', keys: _glyphKeys(_latinLetterCodes)),
      (title: 'Цифры', keys: _glyphKeys(_digitCodes)),
    ]);

// Ё (U+0401) стоит после Е (U+0415), как в алфавите.
final List<int> _russianLetterCodes = [
  for (var c = 0x410; c <= 0x415; c++) c,
  0x401,
  for (var c = 0x416; c <= 0x42F; c++) c,
];
final List<int> _latinLetterCodes = [for (var c = 0x41; c <= 0x5A; c++) c];
final List<int> _digitCodes = [for (var c = 0x30; c <= 0x39; c++) c];

List<String> _glyphKeys(List<int> codes) => List<String>.unmodifiable([
  for (final code in codes) '$glyphIconKeyPrefix${String.fromCharCode(code)}',
]);

/// Префикс ключа «символ вместо иконки»: `glyph:Ж`, `glyph:D`, `glyph:5`.
const String glyphIconKeyPrefix = 'glyph:';

/// Разрешённые символы: 33 русские заглавные (с Ё), 26 латинских, цифры 0-9.
/// Коды заданы числами, чтобы похожие русские и латинские буквы не спутались.
final Map<String, String> _glyphNames = _buildGlyphNames();

Map<String, String> _buildGlyphNames() {
  final names = <String, String>{};
  void addRange(int from, int to, String prefix) {
    for (var code = from; code <= to; code++) {
      final char = String.fromCharCode(code);
      names[char] = '$prefix $char';
    }
  }

  // А-Я (U+0410..U+042F), затем Ё (U+0401).
  addRange(0x410, 0x42F, 'Буква');
  names[String.fromCharCode(0x401)] = 'Буква ${String.fromCharCode(0x401)}';
  addRange(0x41, 0x5A, 'Латинская буква');
  addRange(0x30, 0x39, 'Цифра');
  return Map<String, String>.unmodifiable(names);
}

/// Символ из ключа `glyph:<символ>`, если ключ именно такой и символ
/// разрешён; иначе `null`.
String? categoryGlyphFor(String iconKey) {
  if (!iconKey.startsWith(glyphIconKeyPrefix)) return null;
  final char = iconKey.substring(glyphIconKeyPrefix.length);
  return _glyphNames.containsKey(char) ? char : null;
}

/// Иконка по ключу из `Category.iconKey`; для неизвестного ключа (и для
/// символа, который рисует `CategoryIconView`, а не шрифт иконок) —
/// [fallbackCategoryIcon].
IconData categoryIconFor(String iconKey) =>
    _categoryIcons[iconKey]?.icon ?? fallbackCategoryIcon;

/// Русское название иконки по ключу (для скринридера); для неизвестного ключа —
/// [fallbackCategoryIconName].
String categoryIconName(String iconKey) {
  final glyph = categoryGlyphFor(iconKey);
  if (glyph != null) return _glyphNames[glyph]!;
  return _categoryIcons[iconKey]?.name ?? fallbackCategoryIconName;
}

/// Известен ли ключ таблице (иконка Material или разрешённый символ).
bool isKnownCategoryIconKey(String iconKey) =>
    _categoryIcons.containsKey(iconKey) || categoryGlyphFor(iconKey) != null;
