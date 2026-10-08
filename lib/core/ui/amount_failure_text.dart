import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/money/parse_amount.dart';

/// Пример суммы для подсказок: «1 234,56» (число без знака валюты).
///
/// Строится через [formatMoney], а не набирается руками: так пробел между
/// тысячами всегда тот же неразрывный, что и во всём приложении, и пример
/// не разорвётся на две строки.
String _exampleAmount(CurrencyInfo currency) => formatMoney(
  Money.fromMinor(123456, currency.code),
  currency: currency,
  withCurrencySymbol: false,
);

/// Предельная сумма с валютой, например «1 000 000 000 000,00 ₽». Берётся из
/// [maxInputMinorUnits], поэтому при смене предела текст обновится сам.
String _maxAmount(CurrencyInfo currency) => formatMoney(
  Money.fromMinor(maxInputMinorUnits, currency.code),
  currency: currency,
);

/// Русский текст для пользователя по причине отказа разбора суммы.
///
/// [currency] — валюта поля (по умолчанию рубль). Для рубля тексты прежние;
/// для других валют тексты про знаки после запятой и про предел называют
/// знаки и предел этой валюты.
///
/// `switch` без ветки по умолчанию: при новой причине в
/// [AmountParseFailure] компилятор потребует добавить здесь текст.
String amountFailureMessage(
  AmountParseFailure failure, {
  CurrencyInfo? currency,
}) {
  final info = currency ?? currencyInfoFor(rubCurrencyCode);
  final isRuble = info.code == rubCurrencyCode;
  switch (failure) {
    case AmountParseFailure.empty:
      return 'Введите сумму';
    case AmountParseFailure.notANumber:
      return 'Введите сумму цифрами. Пример: ${_exampleAmount(info)}';
    case AmountParseFailure.negative:
      return 'Знак не нужен: доход это или расход, зависит от нажатой кнопки';
    case AmountParseFailure.tooManyDecimals:
      if (isRuble) {
        return 'После запятой или точки — не больше двух цифр. '
            'Тысячи пишите без точки: 1234';
      }
      if (info.digits == 0) {
        return 'В этой валюте нет дробной части: введите целое число';
      }
      return 'Не больше ${info.digits} '
          '${info.digits == 1 ? 'знака' : 'знаков'} после запятой';
    case AmountParseFailure.tooManySeparators:
      return 'Слишком много запятых или точек. Пример: ${_exampleAmount(info)}';
    case AmountParseFailure.tooLarge:
      if (isRuble) {
        return 'Слишком большая сумма (не больше ${_maxAmount(info)})';
      }
      return 'Не больше ${_maxAmount(info)}';
  }
}
