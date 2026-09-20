import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/categories/domain/default_categories.dart';

void main() {
  group('defaultCategories', () {
    List<DefaultCategory> ofKind(CategoryKind kind) =>
        defaultCategories.where((c) => c.kind == kind).toList();

    test('has 10 expense and 4 income categories', () {
      expect(defaultCategories, hasLength(14));
      expect(ofKind(CategoryKind.expense), hasLength(10));
      expect(ofKind(CategoryKind.income), hasLength(4));
    });

    test('expense names and order are as approved', () {
      expect(ofKind(CategoryKind.expense).map((c) => c.name).toList(), [
        'Продукты',
        'Кафе',
        'Транспорт',
        'Дом',
        'Здоровье',
        'Одежда',
        'Развлечения',
        'Связь',
        'Подарки',
        'Прочее',
      ]);
    });

    test('income names and order are as approved', () {
      expect(ofKind(CategoryKind.income).map((c) => c.name).toList(), [
        'Зарплата',
        'Подработка',
        'Подарок',
        'Прочее',
      ]);
    });

    test('names are unique within a kind', () {
      for (final kind in CategoryKind.values) {
        final names = ofKind(kind).map((c) => c.name).toList();
        expect(names.toSet(), hasLength(names.length), reason: kind.name);
      }
    });

    test('icon keys are not empty', () {
      for (final template in defaultCategories) {
        expect(template.iconKey.trim(), isNotEmpty, reason: template.name);
      }
    });

    test('every entry passes the Category rules', () {
      for (final template in defaultCategories) {
        final category = Category.topLevel(
          id: 'id',
          kind: template.kind,
          name: template.name,
          iconKey: template.iconKey,
          sortOrder: 0,
        );
        expect(category.name, template.name, reason: template.name);
        expect(category.isTopLevel, isTrue);
      }
    });
  });
}
