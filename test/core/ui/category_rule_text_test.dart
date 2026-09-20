import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/category_rule_text.dart';
import 'package:money_app/features/categories/domain/category_rules.dart';

void main() {
  test('у каждого правила есть непустой русский текст', () {
    for (final rule in CategoryRule.values) {
      final text = categoryRuleMessage(rule);
      expect(text, isNotEmpty, reason: '$rule');
      expect(text, matches(RegExp('[А-Яа-я]')), reason: '$rule');
    }
  });

  test('исправимые правила говорят, что делать', () {
    expect(
      categoryRuleMessage(CategoryRule.duplicateName),
      'Такая категория уже есть. Выберите другое название',
    );
    expect(
      categoryRuleMessage(CategoryRule.emptyName),
      'Введите название категории',
    );
    expect(
      categoryRuleMessage(CategoryRule.nameTooLong),
      'Название слишком длинное: не больше 40 символов',
    );
    expect(categoryRuleMessage(CategoryRule.emptyIconKey), 'Выберите иконку');
  });

  test('правила «не должно случаться» дают общий текст', () {
    for (final rule in [
      CategoryRule.negativeSortOrder,
      CategoryRule.parentMustBeTopLevel,
      CategoryRule.kindMismatch,
    ]) {
      expect(
        categoryRuleMessage(rule),
        categorySaveFailedText,
        reason: '$rule',
      );
    }
  });
}
