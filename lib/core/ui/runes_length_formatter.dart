import 'dart:math' as math;

import 'package:flutter/services.dart';

/// Число символов в строке так, как его считает `domain`: кодовыми точками
/// Юникода (`text.runes.length`), а не единицами UTF-16 (`text.length`).
///
/// Русская буква и обычный эмодзи (в том числе «парный», из двух единиц UTF-16)
/// — по одному символу. Составной эмодзи (флаг, семья) состоит из нескольких
/// кодовых точек и считается по числу этих точек.
int runesLength(String text) => text.runes.length;

/// Форматтер поля ввода: не пускает в поле больше [maxRunes] кодовых точек.
///
/// Встроенный `maxLength` считает единицы UTF-16, и эмодзи «съедают» лимит
/// вдвое быстрее; `domain` же считает кодовыми точками (`runes`). Чтобы экран и
/// `domain` не спорили, лимит на экране считается так же.
///
/// Если после правки текст длиннее лимита, лишнее отбрасывается у вставленной
/// части (той, что слева от курсора), а текст справа от курсора сохраняется.
/// Обрезка идёт по границе кодовой точки, поэтому суррогатная пара не
/// разрывается. Курсор встаёт в конец оставленного.
class RunesLengthFormatter extends TextInputFormatter {
  const RunesLengthFormatter(this.maxRunes) : assert(maxRunes >= 0);

  final int maxRunes;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (runesLength(text) <= maxRunes) return newValue;

    final selection = newValue.selection;
    final cursor = selection.isValid && selection.end >= 0
        ? math.min(selection.end, text.length)
        : text.length;
    final before = text.substring(0, cursor).runes.toList();
    final after = text.substring(cursor).runes.toList();

    // Хвост справа от курсора сохраняем целиком, если он сам влезает.
    final keepAfter = math.min(after.length, maxRunes);
    final keepBefore = math.min(before.length, maxRunes - keepAfter);
    final head = String.fromCharCodes(before.take(keepBefore));
    final tail = String.fromCharCodes(after.take(keepAfter));

    return TextEditingValue(
      text: head + tail,
      selection: TextSelection.collapsed(offset: head.length),
    );
  }
}
