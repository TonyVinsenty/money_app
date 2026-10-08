import 'package:flutter/services.dart';

/// Разделитель разрядов в поле: неразрывный пробел (U+00A0), тот же, что ставит
/// `formatMoney` (`formatMoney` берёт его из данных русской локали). Так текст
/// поля и текст на экране выглядят одинаково, а `parseAmount` понимает оба.
/// Символ собран из кода, а не набран, чтобы в исходнике не было невидимого.
final String _groupSeparator = String.fromCharCode(0x00A0);

/// Форматтер поля суммы: приводит текст к виду «12 345,6», пока человек печатает.
///
/// Правила:
/// - печатаются только цифры `0-9`, запятая и точка; пробелы любого вида
///   отбрасываются и расставляются заново; всё остальное (буквы, минус, «₽»)
///   молча пропадает;
/// - точка превращается в запятую;
/// - разряды целой части группируются по три через неразрывный пробел;
/// - если в результате оказалось больше одного разделителя или больше
///   [maxDecimals] цифр после него (при 0 — любой разделитель), ввод отклоняется целиком: возвращается прежнее значение;
/// - ведущие нули: «007» становится «7», «00» — «0» (лишние нули впереди
///   бесполезны, а цифра после единственного нуля заменяет его), «0» и «0,5»
///   остаются; голая «,5» дополняется до «0,5»;
/// - предела суммы нет: это дело `parseAmount` (ошибка `tooLarge`);
/// - итог всегда разбирается `parseAmount` (кроме пустой строки).
///
/// Курсор: позиция считается по «значимым» символам (цифрам и разделителю) слева
/// от него. После пересборки строки курсор ставится сразу за тем же числом
/// значимых символов, поэтому он не прыгает в начало при группировке и остаётся
/// на месте при вставке из буфера и правке в середине строки.
///
/// Удаление пробела-разделителя (backspace сразу за ним или delete перед ним)
/// стирает соседнюю цифру, иначе пробел просто вернулся бы на место и курсор
/// «завис» бы.
class AmountInputFormatter extends TextInputFormatter {
  /// [maxDecimals] — знаков после запятой у валюты (по умолчанию 2, как у
  /// рубля); при 0 запятая и точка не вводятся.
  const AmountInputFormatter({this.maxDecimals = 2});

  final int maxDecimals;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var kept = _keep(newValue.text);
    final oldKept = _keep(oldValue.text);
    final selection = newValue.selection;

    // Позиции курсора (выделения) в значимых символах.
    var base = selection.isValid
        ? _countBefore(newValue.text, selection.baseOffset)
        : kept.length;
    var extent = selection.isValid
        ? _countBefore(newValue.text, selection.extentOffset)
        : kept.length;

    // Значимое не изменилось, а строка стала короче: стёрт только пробел.
    if (selection.isValid &&
        selection.isCollapsed &&
        kept == oldKept &&
        newValue.text.length < oldValue.text.length &&
        oldValue.selection.isValid &&
        oldValue.selection.isCollapsed) {
      final oldOffset = oldValue.selection.baseOffset;
      final newOffset = selection.baseOffset;
      final int? index = oldOffset == newOffset + 1
          ? base -
                1 // backspace: стираем цифру перед пробелом
          : oldOffset == newOffset
          ? base // delete: стираем цифру после пробела
          : null;
      if (index != null && index >= 0 && index < kept.length) {
        kept = kept.substring(0, index) + kept.substring(index + 1);
        base = index;
        extent = index;
      }
    }

    if (kept.isEmpty) {
      return const TextEditingValue(
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final parts = kept.split(',');
    if (parts.length > 2) return oldValue; // второй разделитель
    final hasSeparator = parts.length == 2;
    if (hasSeparator && maxDecimals == 0) {
      return oldValue; // у этой валюты нет дробной части
    }
    if (hasSeparator && parts[1].length > maxDecimals) {
      return oldValue; // лишняя цифра после разделителя
    }

    // Ведущие нули целой части.
    var whole = parts[0];
    var strippedZeros = 0;
    while (whole.length > 1 && whole.startsWith('0')) {
      whole = whole.substring(1);
      strippedZeros++;
    }
    base -= base < strippedZeros ? base : strippedZeros;
    extent -= extent < strippedZeros ? extent : strippedZeros;

    // «,5» -> «0,5»: дописанный нуль сдвигает курсор, если он был после запятой.
    if (whole.isEmpty) {
      whole = '0';
      if (base > 0) base++;
      if (extent > 0) extent++;
    }

    final text = _group(whole) + (hasSeparator ? ',${parts[1]}' : '');
    final significantCount =
        whole.length +
        (hasSeparator ? 1 : 0) +
        (hasSeparator ? parts[1].length : 0);
    return TextEditingValue(
      text: text,
      selection: TextSelection(
        baseOffset: _offsetAfter(text, base.clamp(0, significantCount)),
        extentOffset: _offsetAfter(text, extent.clamp(0, significantCount)),
      ),
    );
  }
}

bool _isDigit(int unit) => unit >= 0x30 && unit <= 0x39;

/// Оставляет цифры и разделитель; точку меняет на запятую, остальное выбрасывает.
String _keep(String text) {
  final buffer = StringBuffer();
  for (final unit in text.codeUnits) {
    if (_isDigit(unit)) {
      buffer.writeCharCode(unit);
    } else if (unit == 0x2C || unit == 0x2E) {
      buffer.write(',');
    }
  }
  return buffer.toString();
}

/// Сколько значимых символов в [text] левее позиции [offset].
int _countBefore(String text, int offset) {
  final end = offset.clamp(0, text.length);
  return _keep(text.substring(0, end)).length;
}

/// Позиция сразу за [count]-м значимым символом [text] (0 — в самом начале).
int _offsetAfter(String text, int count) {
  if (count <= 0) return 0;
  var seen = 0;
  for (var i = 0; i < text.length; i++) {
    if (text[i] != _groupSeparator) seen++;
    if (seen == count) return i + 1;
  }
  return text.length;
}

/// Группирует цифры по три справа налево: «1234567» -> «1 234 567».
String _group(String digits) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(_groupSeparator);
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
