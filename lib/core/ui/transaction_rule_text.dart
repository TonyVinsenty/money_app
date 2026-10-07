import 'package:money_app/features/transactions/domain/transaction_rules.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Общий текст, когда сохранить не удалось и человек ничем помочь не может:
/// ошибка программиста, сбой базы, любое неожиданное исключение.
const String transactionSaveFailedText =
    'Не удалось сохранить. Попробуйте ещё раз';

/// Русский текст для пользователя по нарушенному правилу операции.
///
/// Правила делятся на два вида (ROADMAP, «Рекомендации UX-ревью вехи 2B»):
/// - исправимые пользователем (комментарий, категория, вид категории, архив):
///   у них свой понятный текст, человек выбирает другое и продолжает;
/// - «не должно случаться» ([TransactionRule.negativeAmount],
///   [TransactionRule.occurredAtNotUtc], [TransactionRule.categoryMustBeTopLevel]):
///   экраны их не допускают, поэтому здесь запасной общий
///   [transactionSaveFailedText].
///
/// [type] нужен только для [TransactionRule.typeKindMismatch]: текст называет,
/// что вводит человек. `switch` без ветки по умолчанию: при новом правиле
/// компилятор потребует добавить текст.
String transactionRuleMessage(
  TransactionRule rule, {
  required TransactionType type,
}) {
  switch (rule) {
    case TransactionRule.noteTooLong:
      return 'Комментарий слишком длинный: '
          'не больше $transactionNoteMaxLength символов';
    case TransactionRule.emptyCategoryId:
      return 'Выберите категорию';
    case TransactionRule.typeKindMismatch:
      final entered = type == TransactionType.income ? 'доход' : 'расход';
      final categoryFor = type == TransactionType.income
          ? 'расходов'
          : 'доходов';
      return 'Эта категория из другого вида: она для $categoryFor, '
          'а вы вводите $entered. Выберите другую категорию';
    case TransactionRule.subcategoryNotOfCategory:
      return 'Эта подкатегория относится к другой категории. '
          'Выберите подкатегорию заново или нажмите «Без подкатегории»';
    case TransactionRule.categoryArchived:
      return 'Эта категория в архиве. Выберите другую';
    case TransactionRule.accountArchived:
      return 'Этот счёт в архиве. Выберите другой счёт или «Без счёта»';
    case TransactionRule.accountCurrencyMismatch:
      return 'Валюта счёта не совпадает с валютой операции. '
          'Выберите другой счёт';
    case TransactionRule.negativeAmount:
    case TransactionRule.occurredAtNotUtc:
    case TransactionRule.categoryMustBeTopLevel:
      return transactionSaveFailedText;
  }
}
