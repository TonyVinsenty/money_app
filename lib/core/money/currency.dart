/// Код рубля по ISO 4217.
const String rubCurrencyCode = 'RUB';

final RegExp _currencyCodePattern = RegExp(r'^[A-Z][A-Z0-9]{2,9}$');
final RegExp _isoCurrencyCodePattern = RegExp(r'^[A-Z]{3}$');

/// Код валюты подходит, если это 3-10 заглавных латинских букв и цифр, а
/// первая - буква (ADR 0010, п. 16.3): `RUB`, `USDT`, `BTC2`.
///
/// Проверяется только форма кода, а не наличие такой валюты в мире.
bool isValidCurrencyCode(String code) => _currencyCodePattern.hasMatch(code);

/// Код обычной (ISO 4217) валюты: ровно три заглавные латинские буквы.
/// Операции хранятся только в таких валютах (ADR 0010, п. 16.9).
bool isIsoCurrencyCode(String code) => _isoCurrencyCodePattern.hasMatch(code);
