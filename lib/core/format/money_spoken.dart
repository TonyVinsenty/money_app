import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';

/// Сумма словами для скринридера: «1234 рубля 50 копеек».
///
/// Числа пишутся цифрами, склоняется только слово («рубль/рубля/рублей»,
/// «копейка/копейки/копеек»). Разделителя разрядов внутри числа нет: скринридер
/// читает «1234» как одно число, а «1 234» с пробелом может прочитать как два
/// («один, двести тридцать четыре»), особенно если пробел неразрывный.
///
/// Рубль:
/// - копейки не читаются, если их нет: «5 рублей», а не «5 рублей 0 копеек»;
/// - если есть только копейки, рубли всё равно называются: «0 рублей 50 копеек»
///   (на слух однозначнее, чем «50 копеек»);
/// - ноль читается «0 рублей»;
/// - отрицательная сумма получает приставку «минус ».
///
/// Остальные валюты (ADR 0010, п. 16.6), [currency] по умолчанию берётся из
/// каталога по коду суммы:
/// - со словами: число с запятой (нули в конце срезаны) и слово: целое - по
///   правилу 1/2/5 («2 доллара»), дробное - вторая форма («12,5 доллара»);
/// - без слов (и своя валюта): «число, название» - «1500, ABC».
///
/// Считается целыми числами, без дробных. Только для показа и озвучки в UI
/// (ADR 0004).
String spokenMoney(Money money, {CurrencyInfo? currency}) {
  final info = currency ?? currencyInfoFor(money.currency, digits: 2);
  if (info.code != rubCurrencyCode) return _spokenOther(money, info);

  final minor = money.minorUnits;
  // Модуль берём у каждой части отдельно: у самого маленького int модуль всей
  // суммы остаётся отрицательным, а части — нет (как в formatMoney).
  final whole = (minor ~/ 100).abs();
  final fraction = minor.remainder(100).abs();

  final buffer = StringBuffer();
  if (minor < 0) {
    buffer.write('минус ');
  }
  buffer
    ..write(whole)
    ..write(' ')
    ..write(_plural(whole, 'рубль', 'рубля', 'рублей'));
  if (fraction > 0) {
    buffer
      ..write(' ')
      ..write(fraction)
      ..write(' ')
      ..write(_plural(fraction, 'копейка', 'копейки', 'копеек'));
  }
  return buffer.toString();
}

/// Выбирает форму слова по числу [n] (n >= 0): 1 (кроме 11) — [one],
/// 2–4 (кроме 12–14) — [few], остальное — [many].
String _plural(int n, String one, String few, String many) {
  final lastTwo = n % 100;
  if (lastTwo >= 11 && lastTwo <= 14) return many;
  return switch (n % 10) {
    1 => one,
    2 || 3 || 4 => few,
    _ => many,
  };
}

/// Не рубль: число без разделителя разрядов и слово или название.
String _spokenOther(Money money, CurrencyInfo info) {
  final minor = money.minorUnits;
  final divisor = pow10(info.digits);
  final whole = (minor ~/ divisor).abs();
  // Дробная часть без нулей в конце: «0,0015», а не «0,00150000».
  var fraction = info.digits == 0
      ? ''
      : minor.remainder(divisor).abs().toString().padLeft(info.digits, '0');
  var end = fraction.length;
  while (end > 0 && fraction[end - 1] == '0') {
    end--;
  }
  fraction = fraction.substring(0, end);

  final number = fraction.isEmpty ? '$whole' : '$whole,$fraction';
  final forms = info.forms;
  final String tail;
  if (forms == null) {
    tail = ', ${info.name}';
  } else if (fraction.isNotEmpty) {
    tail = ' ${forms.few}';
  } else {
    tail = ' ${_plural(whole, forms.one, forms.few, forms.many)}';
  }
  return '${minor < 0 ? 'минус ' : ''}$number$tail';
}
