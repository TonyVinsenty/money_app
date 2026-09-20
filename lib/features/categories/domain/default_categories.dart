import 'package:money_app/features/categories/domain/category_kind.dart';

/// Категория из набора «по умолчанию»: то, с чего приложение начинает при
/// первом запуске. Это шаблон без id и порядка: их назначает засев.
final class DefaultCategory {
  const DefaultCategory({
    required this.kind,
    required this.name,
    required this.iconKey,
  });

  /// Доход или расход.
  final CategoryKind kind;

  /// Имя категории.
  final String name;

  /// Строковый ключ иконки.
  final String iconKey;
}

/// Набор категорий по умолчанию (утверждён пользователем): 10 расходных и
/// 4 доходных. Порядок в списке = порядок показа внутри каждого вида.
///
/// Ключи иконок ПРЕДВАРИТЕЛЬНЫЕ: это названия Material Icons. Финальный
/// фиксированный набор (около 30 иконок) будет утверждён на шаге 2.33.
const List<DefaultCategory> defaultCategories = [
  // Расходы.
  DefaultCategory(
    kind: CategoryKind.expense,
    name: 'Продукты',
    iconKey: 'shopping_cart',
  ),
  DefaultCategory(
    kind: CategoryKind.expense,
    name: 'Кафе',
    iconKey: 'restaurant',
  ),
  DefaultCategory(
    kind: CategoryKind.expense,
    name: 'Транспорт',
    iconKey: 'directions_bus',
  ),
  DefaultCategory(kind: CategoryKind.expense, name: 'Дом', iconKey: 'house'),
  DefaultCategory(
    kind: CategoryKind.expense,
    name: 'Здоровье',
    iconKey: 'medical_services',
  ),
  DefaultCategory(
    kind: CategoryKind.expense,
    name: 'Одежда',
    iconKey: 'checkroom',
  ),
  DefaultCategory(
    kind: CategoryKind.expense,
    name: 'Развлечения',
    iconKey: 'sports_esports',
  ),
  DefaultCategory(
    kind: CategoryKind.expense,
    name: 'Связь',
    iconKey: 'phone_android',
  ),
  DefaultCategory(
    kind: CategoryKind.expense,
    name: 'Подарки',
    iconKey: 'card_giftcard',
  ),
  DefaultCategory(
    kind: CategoryKind.expense,
    name: 'Прочее',
    iconKey: 'more_horiz',
  ),
  // Доходы.
  DefaultCategory(
    kind: CategoryKind.income,
    name: 'Зарплата',
    iconKey: 'payments',
  ),
  DefaultCategory(
    kind: CategoryKind.income,
    name: 'Подработка',
    iconKey: 'work',
  ),
  DefaultCategory(
    kind: CategoryKind.income,
    name: 'Подарок',
    iconKey: 'redeem',
  ),
  DefaultCategory(
    kind: CategoryKind.income,
    name: 'Прочее',
    iconKey: 'more_horiz',
  ),
];
