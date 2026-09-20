import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/categories/domain/category_rules.dart';

void main() {
  test('максимальная длина имени равна 40', () {
    expect(categoryNameMaxLength, 40);
  });

  test('исключение хранит правило и сообщение по умолчанию', () {
    for (final rule in CategoryRule.values) {
      final e = CategoryRuleException(rule);
      expect(e.rule, rule);
      expect(e.message, isNotEmpty);
    }
  });

  test('можно передать своё сообщение', () {
    final e = CategoryRuleException(CategoryRule.emptyName, 'custom');
    expect(e.message, 'custom');
  });

  test('toString содержит имя правила и сообщение', () {
    final e = CategoryRuleException(CategoryRule.kindMismatch);
    expect(e.toString(), contains('kindMismatch'));
    expect(e.toString(), contains(e.message));
  });

  test('это Exception, его можно поймать по типу', () {
    expect(
      () => throw CategoryRuleException(CategoryRule.nameTooLong),
      throwsA(isA<CategoryRuleException>()),
    );
  });
}
