import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/category_icons.dart';
import 'package:money_app/features/categories/domain/default_categories.dart';

void main() {
  test('все ключи иконок из набора по умолчанию известны таблице', () {
    for (final category in defaultCategories) {
      expect(
        isKnownCategoryIconKey(category.iconKey),
        isTrue,
        reason: 'нет иконки для "${category.iconKey}" (${category.name})',
      );
      expect(categoryIconFor(category.iconKey), isNot(fallbackCategoryIcon));
    }
  });

  test('неизвестный ключ даёт запасную иконку', () {
    expect(isKnownCategoryIconKey('no_such_icon'), isFalse);
    expect(categoryIconFor('no_such_icon'), fallbackCategoryIcon);
    expect(categoryIconFor(''), fallbackCategoryIcon);
  });
}
