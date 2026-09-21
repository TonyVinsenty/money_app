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

  test('список ключей нельзя изменить', () {
    expect(() => categoryIconKeys.add('x'), throwsUnsupportedError);
  });

  test('неизвестный ключ даёт запасную иконку и название', () {
    expect(isKnownCategoryIconKey('no_such_icon'), isFalse);
    expect(categoryIconFor('no_such_icon'), fallbackCategoryIcon);
    expect(categoryIconFor(''), fallbackCategoryIcon);
    expect(categoryIconName('no_such_icon'), fallbackCategoryIconName);
  });
}
