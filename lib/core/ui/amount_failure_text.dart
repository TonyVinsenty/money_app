import 'package:money_app/core/money/parse_amount.dart';

/// Русский текст для пользователя по причине отказа разбора суммы.
///
/// `switch` без ветки по умолчанию: при новой причине в
/// [AmountParseFailure] компилятор потребует добавить здесь текст.
String amountFailureMessage(AmountParseFailure failure) {
  switch (failure) {
    case AmountParseFailure.empty:
      return 'Введите сумму';
    case AmountParseFailure.notANumber:
      return 'Это не число. Пример: 1 234,56';
    case AmountParseFailure.negative:
      return 'Минус вводить не нужно: доход или расход выбирается кнопкой';
    case AmountParseFailure.tooManyDecimals:
      return 'Не больше двух знаков после запятой';
    case AmountParseFailure.tooManySeparators:
      return 'Слишком много запятых или точек. Пример: 1 234,56';
    case AmountParseFailure.tooLarge:
      return 'Слишком большая сумма';
  }
}
