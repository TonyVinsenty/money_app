import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/money/parse_amount.dart';

/// Пример суммы для подсказок: «1 234,56» (число без знака валюты).
///
/// Строится через [formatMoney], а не набирается руками: так пробел между
/// тысячами всегда тот же неразрывный, что и во всём приложении, и пример
/// не разорвётся на две строки.
String _exampleAmount() => formatMoney(
  Money.fromMinor(123456, rubCurrencyCode),
  withCurrencySymbol: false,
);

/// Предельная сумма с валютой, например «1 000 000 000 000,00 ₽». Берётся из
/// [maxInputMajorUnits], поэтому при смене предела текст обновится сам.
String _maxAmount() =>
    formatMoney(Money.fromMajorParts(maxInputMajorUnits, 0, rubCurrencyCode));

/// Русский текст для пользователя по причине отказа разбора суммы.
///
/// `switch` без ветки по умолчанию: при новой причине в
/// [AmountParseFailure] компилятор потребует добавить здесь текст.
String amountFailureMessage(AmountParseFailure failure) {
  switch (failure) {
    case AmountParseFailure.empty:
      return 'Введите сумму';
    case AmountParseFailure.notANumber:
      return 'Введите сумму цифрами. Пример: ${_exampleAmount()}';
    case AmountParseFailure.negative:
      return 'Знак не нужен: доход это или расход, зависит от нажатой кнопки';
    case AmountParseFailure.tooManyDecimals:
      return 'После запятой или точки — не больше двух цифр. '
          'Тысячи пишите без точки: 1234';
    case AmountParseFailure.tooManySeparators:
      return 'Слишком много запятых или точек. Пример: ${_exampleAmount()}';
    case AmountParseFailure.tooLarge:
      return 'Слишком большая сумма (не больше ${_maxAmount()})';
  }
}
