import 'package:flutter/material.dart';

/// Иконка на случай, если ключ неизвестен (например, его сохранила будущая
/// версия приложения). Категория при этом остаётся видимой и нажимаемой.
const IconData fallbackCategoryIcon = Icons.category_outlined;

/// Название иконки, если ключ неизвестен.
const String fallbackCategoryIconName = 'Категория';

/// Иконка и её русское название (название читает скринридер).
typedef _IconEntry = ({IconData icon, String name});

/// Фиксированный набор иконок для категорий: «ключ -> иконка и название».
///
/// В базе хранится только строковый ключ (snake_case), а не код иконки: так
/// иконка не «ломается» в релизной сборке. Порядок записей — порядок в сетке
/// выбора; первая иконка используется по умолчанию. Ключи 13 категорий по
/// умолчанию менять нельзя: они уже лежат в базе.
const Map<String, _IconEntry> _categoryIcons = <String, _IconEntry>{
  'shopping_cart': (icon: Icons.shopping_cart, name: 'Корзина'),
  'restaurant': (icon: Icons.restaurant, name: 'Ресторан'),
  'directions_bus': (icon: Icons.directions_bus, name: 'Автобус'),
  'house': (icon: Icons.house, name: 'Дом'),
  'medical_services': (icon: Icons.medical_services, name: 'Медицина'),
  'checkroom': (icon: Icons.checkroom, name: 'Одежда'),
  'sports_esports': (icon: Icons.sports_esports, name: 'Игры'),
  'phone_android': (icon: Icons.phone_android, name: 'Телефон'),
  'card_giftcard': (icon: Icons.card_giftcard, name: 'Карта'),
  'more_horiz': (icon: Icons.more_horiz, name: 'Другое'),
  'payments': (icon: Icons.payments, name: 'Деньги'),
  'work': (icon: Icons.work, name: 'Работа'),
  'redeem': (icon: Icons.redeem, name: 'Подарок'),
  'local_cafe': (icon: Icons.local_cafe, name: 'Кофе'),
  'local_gas_station': (icon: Icons.local_gas_station, name: 'Заправка'),
  'directions_car': (icon: Icons.directions_car, name: 'Машина'),
  'flight': (icon: Icons.flight, name: 'Самолёт'),
  'school': (icon: Icons.school, name: 'Учёба'),
  'fitness_center': (icon: Icons.fitness_center, name: 'Спорт'),
  'pets': (icon: Icons.pets, name: 'Питомцы'),
  'child_care': (icon: Icons.child_care, name: 'Дети'),
  'movie': (icon: Icons.movie, name: 'Кино'),
  'savings': (icon: Icons.savings, name: 'Копилка'),
  'account_balance': (icon: Icons.account_balance, name: 'Банк'),
  'trending_up': (icon: Icons.trending_up, name: 'График'),
  'wifi': (icon: Icons.wifi, name: 'Интернет'),
  'build': (icon: Icons.build, name: 'Инструменты'),
  'spa': (icon: Icons.spa, name: 'Красота'),
  'local_pharmacy': (icon: Icons.local_pharmacy, name: 'Аптека'),
  'shopping_bag': (icon: Icons.shopping_bag, name: 'Сумка'),
};

/// Ключи иконок для выбора, в порядке показа. Первый — иконка по умолчанию.
final List<String> categoryIconKeys = List<String>.unmodifiable(
  _categoryIcons.keys,
);

/// Иконка по ключу из `Category.iconKey`; для неизвестного ключа —
/// [fallbackCategoryIcon].
IconData categoryIconFor(String iconKey) =>
    _categoryIcons[iconKey]?.icon ?? fallbackCategoryIcon;

/// Русское название иконки по ключу (для скринридера); для неизвестного ключа —
/// [fallbackCategoryIconName].
String categoryIconName(String iconKey) =>
    _categoryIcons[iconKey]?.name ?? fallbackCategoryIconName;

/// Известен ли ключ таблице.
bool isKnownCategoryIconKey(String iconKey) =>
    _categoryIcons.containsKey(iconKey);
