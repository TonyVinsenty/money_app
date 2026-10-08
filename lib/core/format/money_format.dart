import 'package:intl/intl.dart';
import 'package:money_app/core/money/currency_catalog.dart';
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

/// Символ валюты для показа: «₽» для RUB, «$» для USD, «€» для EUR; для
/// валют без привычного символа и не из каталога - сам код.
String currencySymbol(String currency) =>
    catalogCurrency(currency)?.symbol ?? currency;

/// 10 в степени [digits] (0-8), целым числом.
int pow10(int digits) {
  var result = 1;
  for (var i = 0; i < digits; i++) {
    result *= 10;
  }
  return result;
}

/// Форматирует сумму для показа: «12 345,67 ₽».
///
/// Знаков после запятой столько, сколько у валюты ([currency], по умолчанию
/// запись каталога по коду суммы; ADR 0010, п. 16.5): у обычной валюты всегда
/// все знаки («150,00 $», «12,345 KWD»); при 0 знаков запятой нет; у крипты и
/// своих валют нули в конце срезаются, но остаётся не меньше двух знаков
/// («0,0015 BTC», «1,00 BTC»). Всегда разделитель разрядов. Отрицательная сумма
/// получает ведущий минус («\u22121 234,50 ₽»), знак «+» не добавляется.
/// С `withCurrencySymbol: false` возвращается только число («12 345,67»).
///
/// Код не из каталога без переданной [currency] - ошибка программиста
/// (`assert`); в релизе берутся 2 знака и код вместо символа.
///
/// Части считаются целочисленно из `minorUnits`, дробные числа не
/// используются. Только для показа в UI: в хранилище деньги остаются целыми.
String formatMoney(
  Money money, {
  CurrencyInfo? currency,
  bool withCurrencySymbol = true,
}) {
  final info = currency ?? currencyInfoFor(money.currency);
  final digits = info.digits;
  final minor = money.minorUnits;
  final divisor = pow10(digits);
  // `~/` и `remainder` считают «от нуля», поэтому берём модуль отдельно у
  // каждой части, а знак ставим один раз в начале. Модуль всей суммы не берём:
  // у самого маленького int он остаётся отрицательным, а части — нет.
  final whole = (minor ~/ divisor).abs();
  var fraction = digits == 0
      ? ''
      : minor.remainder(divisor).abs().toString().padLeft(digits, '0');
  if (info.kind != CurrencyKind.fiat && digits > 2) {
    // Срезаем нули в конце, но оставляем не меньше двух знаков.
    var end = fraction.length;
    while (end > 2 && fraction[end - 1] == '0') {
      end--;
    }
    fraction = fraction.substring(0, end);
  }

  final buffer = StringBuffer();
  if (minor < 0) {
    buffer.write(_minus);
  }
  buffer.write(_wholeFormat.format(whole));
  if (fraction.isNotEmpty) {
    buffer
      ..write(_wholeFormat.symbols.DECIMAL_SEP)
      ..write(fraction);
  }

  if (withCurrencySymbol) {
    buffer
      ..write(_nbsp)
      ..write(info.symbol);
  }
  return buffer.toString();
}
