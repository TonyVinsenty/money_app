import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/transaction_rule_text.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

void main() {
  const expense = TransactionType.expense;

  test('у каждого правила есть непустой русский текст', () {
    for (final type in TransactionType.values) {
      for (final rule in TransactionRule.values) {
        final text = transactionRuleMessage(rule, type: type);
        expect(text, isNotEmpty, reason: '$rule');
        expect(text, matches(RegExp('[А-Яа-я]')), reason: '$rule');
      }
    }
  });

  test('исправимые правила говорят, что делать', () {
    expect(
      transactionRuleMessage(TransactionRule.noteTooLong, type: expense),
      'Комментарий слишком длинный: не больше 200 символов',
    );
    expect(
      transactionRuleMessage(TransactionRule.emptyCategoryId, type: expense),
      'Выберите категорию',
    );
    expect(
      transactionRuleMessage(TransactionRule.categoryArchived, type: expense),
      'Эта категория в архиве. Выберите другую',
    );
    expect(
      transactionRuleMessage(
        TransactionRule.subcategoryNotOfCategory,
        type: expense,
      ),
      contains('Выберите подкатегорию заново'),
    );
  });

  test('typeKindMismatch называет, что вводит человек', () {
    expect(
      transactionRuleMessage(TransactionRule.typeKindMismatch, type: expense),
      'Эта категория из другого вида: она для доходов, а вы вводите расход. '
      'Выберите другую категорию',
    );
    expect(
      transactionRuleMessage(
        TransactionRule.typeKindMismatch,
        type: TransactionType.income,
      ),
      'Эта категория из другого вида: она для расходов, а вы вводите доход. '
      'Выберите другую категорию',
    );
  });

  test('правила «не должно случаться» дают общий текст', () {
    for (final rule in [
      TransactionRule.negativeAmount,
      TransactionRule.occurredAtNotUtc,
      TransactionRule.categoryMustBeTopLevel,
    ]) {
      expect(
        transactionRuleMessage(rule, type: expense),
        transactionSaveFailedText,
        reason: '$rule',
      );
    }
    expect(
      transactionSaveFailedText,
      'Не удалось сохранить. Попробуйте ещё раз',
    );
  });
}
