import 'package:intl/intl.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';

final NumberFormat _wholeFormat = NumberFormat.decimalPattern('ru');

/// Подпись деления шкалы графика: без копеек и знака валюты и короткая, чтобы
/// не съедать ширину: «0», «500», «9 999», «200 тыс.», «12,5 тыс.», «1,5 млн».
///
/// Это только деления шкалы; суммы в тексте по-прежнему показывает
/// `formatMoney`. Всё считается целыми числами: дробная часть («5» в «1,5») —
/// десятая доля, отброшенная вниз. Между числом и «тыс.»/«млн» стоит
/// неразрывный пробел (U+00A0), чтобы подпись не разорвалась.
String formatAxisTick(Money money) {
  final digits = currencyInfoFor(money.currency).digits;
  var divisor = 1;
  for (var i = 0; i < digits; i++) {
    divisor *= 10;
  }
  final minor = money.minorUnits;
  final whole = (minor ~/ divisor).abs();
  final sign = minor < 0 && whole > 0 ? String.fromCharCode(0x2212) : '';
  final nbsp = String.fromCharCode(0x00A0);

  String scaled(int unit, String suffix) {
    final head = whole ~/ unit;
    final tenth = (whole % unit) * 10 ~/ unit;
    final number = _wholeFormat.format(head);
    final fraction = tenth == 0
        ? ''
        : '${_wholeFormat.symbols.DECIMAL_SEP}$tenth';
    return '$sign$number$fraction$nbsp$suffix';
  }

  if (whole >= 1000000) return scaled(1000000, 'млн');
  if (whole >= 10000) return scaled(1000, 'тыс.');
  return '$sign${_wholeFormat.format(whole)}';
}
