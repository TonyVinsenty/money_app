/// Максимальная длина имени категории (после обрезки пробелов).
///
/// Считается в символах (кодовых точках Юникода): `name.runes.length`.
/// Поэтому русская буква и обычный эмодзи занимают по одному символу.
const int categoryNameMaxLength = 40;

/// Правила категорий, которые можно нарушить.
enum CategoryRule {
  /// Имя пустое или состоит только из пробелов.
  emptyName,

  /// Имя длиннее [categoryNameMaxLength] символов.
  nameTooLong,

  /// Ключ иконки пустой или состоит только из пробелов.
  emptyIconKey,

  /// Порядок в списке отрицательный.
  negativeSortOrder,

  /// Родителем выбрана подкатегория: вложенность только в один уровень.
  parentMustBeTopLevel,

  /// Вид подкатегории не совпадает с видом родителя.
  kindMismatch,

  /// Среди не архивных категорий того же вида и уровня уже есть категория с
  /// таким именем (без учёта регистра и пробелов по краям).
  duplicateName,
}

/// Ключ для сравнения имён: без пробелов по краям и без учёта регистра.
///
/// Регистр убирает `toLowerCase()`; для кириллицы и латиницы этого достаточно.
String categoryNameKey(String name) => name.trim().toLowerCase();

/// Ошибка нарушения правила категории.
///
/// Типизированная: по полю [rule] интерфейс выбирает понятный текст для
/// пользователя, а [message] нужен разработчику (логи, тесты).
final class CategoryRuleException implements Exception {
  CategoryRuleException(this.rule, [String? message])
    : message = message ?? _defaultMessage(rule);

  /// Какое правило нарушено.
  final CategoryRule rule;

  /// Описание нарушения по-английски.
  final String message;

  static String _defaultMessage(CategoryRule rule) {
    switch (rule) {
      case CategoryRule.emptyName:
        return 'Category name must not be empty';
      case CategoryRule.nameTooLong:
        return 'Category name must not be longer than '
            '$categoryNameMaxLength characters';
      case CategoryRule.emptyIconKey:
        return 'Category icon key must not be empty';
      case CategoryRule.negativeSortOrder:
        return 'Category sort order must not be negative';
      case CategoryRule.parentMustBeTopLevel:
        return 'Parent of a subcategory must be a top-level category';
      case CategoryRule.kindMismatch:
        return 'Subcategory kind must match the kind of its parent';
      case CategoryRule.duplicateName:
        return 'A category with this name already exists on the same level';
    }
  }

  @override
  String toString() => 'CategoryRuleException(${rule.name}): $message';
}
