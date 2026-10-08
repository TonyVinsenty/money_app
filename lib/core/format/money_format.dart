import 'package:intl/intl.dart';
import 'package:money_app/core/money/money.dart';

/// Неразрывный пробел (U+00A0): между числом и символом валюты. «Неразрывный»
/// значит, что строка не переносится на другую строку в этом месте, и «12 345,67»
/// с «₽» не разорвутся.
final String _nbsp = String.fromCharCode(0x00A0);

/// Настоящий (типографский) минус U+2212. Он шире и заметнее дефиса.
/// Пакет `intl` для русской локали отдаёт обычный дефис, поэтому знак
/// ставим сами.
final String _minus = String.fromCharCode(0x2212);

/// Форматтер целой части для русской локали. Разделитель разрядов берётся из
/// данных локали (у `ru` это неразрывный пробел U+00A0).
final NumberFormat _wholeFormat = NumberFormat.decimalPattern('ru');

/// Символы известных валют; для остальных кодов показываем сам код.
const Map<String, String> _currencySymbols = <String, String>{
  'RUB': '₽',
  'USD': r'$',
  'EUR': '€',
};

/// Символ валюты для показа: «₽» для RUB, «$» для USD, «€» для EUR; для
/// остальных кодов — сам код.
String currencySymbol(String currency) =>
    _currencySymbols[currency] ?? currency;

/// Форматирует сумму для показа: «12 345,67 ₽».
///
/// Всегда две цифры после запятой и всегда разделитель разрядов. Отрицательная
/// сумма получает ведущий минус («\u22121 234,50 ₽»), знак «+» не добавляется.
/// С `withCurrencySymbol: false` возвращается только число («12 345,67»); эту
/// строку понимает `parseAmount`.
///
/// Целая и дробная части считаются целочисленно из `minorUnits`, дробные
/// числа не используются. Число знаков (2) зашито под рубль, доллар, евро
/// (ADR 0004). Только для показа в UI: в хранилище и расчётах деньги остаются
/// целыми копейками.
String formatMoney(Money money, {bool withCurrencySymbol = true}) {
  final minor = money.minorUnits;
  // `~/` и `remainder` считают «от нуля», поэтому берём модуль отдельно у
  // каждой части, а знак ставим один раз в начале. Модуль всей суммы не берём:
  // у самого маленького int он остаётся отрицательным, а части — нет.
  final whole = (minor ~/ 100).abs();
  final fraction = minor.remainder(100).abs();

  final buffer = StringBuffer();
  if (minor < 0) {
    buffer.write(_minus);
  }
  buffer
    ..write(_wholeFormat.format(whole))
    ..write(_wholeFormat.symbols.DECIMAL_SEP)
    ..write(fraction.toString().padLeft(2, '0'));

  if (withCurrencySymbol) {
    buffer
      ..write(_nbsp)
      ..write(currencySymbol(money.currency));
  }
  return buffer.toString();
}
