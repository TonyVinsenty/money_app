import 'package:money_app/features/recurring/domain/recurring_rules.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Общий текст, когда сохранить платёж не удалось и человек ничем помочь не
/// может: ошибка программиста, сбой базы, любое неожиданное исключение.
const String recurringSaveFailedText =
    'Не удалось сохранить. Попробуйте ещё раз';

/// Русский текст для пользователя по нарушенному правилу платежа.
///
/// [type] нужен для [RecurringRule.typeKindMismatch]. `switch` без ветки по
/// умолчанию: при новом правиле компилятор потребует добавить текст.
String recurringRuleMessage(
  RecurringRule rule, {
  required TransactionType type,
}) {
  switch (rule) {
    case RecurringRule.emptyTitle:
      return 'Введите название платежа';
    case RecurringRule.titleTooLong:
      return 'Название слишком длинное: не больше $recurringTitleMaxLength '
          'символов';
    case RecurringRule.nonPositiveAmount:
      return 'Сумма должна быть больше нуля';
    case RecurringRule.everyOutOfRange:
      return 'Повтор: от $recurringEveryMin до $recurringEveryMax';
    case RecurringRule.endsBeforeStart:
      return 'Дата окончания раньше даты первого платежа';
    case RecurringRule.typeKindMismatch:
      final entered = type == TransactionType.income ? 'доход' : 'расход';
      final categoryFor = type == TransactionType.income
          ? 'расходов'
          : 'доходов';
      return 'Эта категория из другого вида: она для $categoryFor, '
          'а вы вводите $entered. Выберите другую категорию';
    case RecurringRule.subcategoryNotOfCategory:
      return 'Эта подкатегория относится к другой категории. '
          'Выберите подкатегорию заново или нажмите «Без подкатегории»';
    case RecurringRule.categoryArchived:
      return 'Эта категория в архиве. Выберите другую';
    case RecurringRule.accountArchived:
      return 'Этот счёт в архиве. Выберите другой счёт или «Без счёта»';
    case RecurringRule.accountCurrencyMismatch:
      return 'Валюта счёта не совпадает с валютой платежа. '
          'Выберите другой счёт';
    case RecurringRule.currencyNotRegular:
    case RecurringRule.emptyId:
    case RecurringRule.categoryMustBeTopLevel:
      return recurringSaveFailedText;
  }
}
