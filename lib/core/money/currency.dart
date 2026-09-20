/// Код рубля по ISO 4217. Пока это единственная валюта приложения.
const String rubCurrencyCode = 'RUB';

final RegExp _currencyCodePattern = RegExp(r'^[A-Z]{3}$');

/// Код валюты подходит, если это ровно три заглавные латинские буквы (ISO 4217).
///
/// Проверяется только форма кода, а не наличие такой валюты в мире:
/// таблицы валют в приложении нет.
bool isValidCurrencyCode(String code) => _currencyCodePattern.hasMatch(code);
