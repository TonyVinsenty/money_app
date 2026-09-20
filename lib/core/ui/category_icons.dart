import 'package:flutter/material.dart';

/// Иконка на случай, если ключ неизвестен (например, его сохранила будущая
/// версия приложения). Категория при этом остаётся видимой и нажимаемой.
const IconData fallbackCategoryIcon = Icons.category_outlined;

/// Таблица «ключ иконки → иконка» для категорий.
///
/// Пока в ней только 13 ключей из набора категорий по умолчанию. Полный
/// фиксированный набор (около 30 иконок) появится на шаге 2.33.
const Map<String, IconData> _categoryIcons = <String, IconData>{
  'shopping_cart': Icons.shopping_cart,
  'restaurant': Icons.restaurant,
  'directions_bus': Icons.directions_bus,
  'house': Icons.house,
  'medical_services': Icons.medical_services,
  'checkroom': Icons.checkroom,
  'sports_esports': Icons.sports_esports,
  'phone_android': Icons.phone_android,
  'card_giftcard': Icons.card_giftcard,
  'more_horiz': Icons.more_horiz,
  'payments': Icons.payments,
  'work': Icons.work,
  'redeem': Icons.redeem,
};

/// Иконка по ключу из `Category.iconKey`; для неизвестного ключа —
/// [fallbackCategoryIcon].
IconData categoryIconFor(String iconKey) =>
    _categoryIcons[iconKey] ?? fallbackCategoryIcon;

/// Известен ли ключ таблице (нужно тестам и будущему выбору иконки).
bool isKnownCategoryIconKey(String iconKey) =>
    _categoryIcons.containsKey(iconKey);
