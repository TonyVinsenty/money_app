import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/runes_length_formatter.dart';

/// Эмодзи из двух единиц UTF-16 (суррогатная пара), но одна кодовая точка.
final _smile = String.fromCharCode(0x1F600);

/// Флаг: две кодовые точки (региональные индикаторы), 4 единицы UTF-16.
final _flag = String.fromCharCodes([0x1F1F7, 0x1F1FA]);

/// Семья: 5 кодовых точек (три эмодзи и два соединителя), 8 единиц UTF-16.
final _family = String.fromCharCodes([
  0x1F468,
  0x200D,
  0x1F469,
  0x200D,
  0x1F467,
]);

/// Применяет форматтер к правке «старый текст -> новый текст, курсор [cursor]»
/// (по умолчанию в конце нового текста).
TextEditingValue _apply(
  int max,
  String oldText,
  String newText, {
  int? cursor,
}) {
  return RunesLengthFormatter(max).formatEditUpdate(
    TextEditingValue(text: oldText),
    TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: cursor ?? newText.length),
    ),
  );
}

void main() {
  test('runesLength считает кодовые точки, а не единицы UTF-16', () {
    expect(runesLength(''), 0);
    expect(runesLength('Привет'), 6);
    expect(runesLength(_smile), 1);
    expect(_smile.length, 2);
    expect(runesLength(_flag), 2);
    expect(runesLength(_family), 5);
  });

  group('RunesLengthFormatter', () {
    test('текст в пределах лимита проходит без изменений', () {
      final result = _apply(5, 'ab', 'abcde');
      expect(result.text, 'abcde');
    });

    test('лишний символ при печати не добавляется', () {
      final result = _apply(5, 'abcde', 'abcdef');
      expect(result.text, 'abcde');
      expect(result.selection, const TextSelection.collapsed(offset: 5));
    });

    test('вставка обрезается до лимита', () {
      final result = _apply(5, 'ab', 'abcdefgh');
      expect(result.text, 'abcde');
      expect(result.selection.baseOffset, 5);
    });

    test('вставка в середину сохраняет текст справа от курсора', () {
      // Было «abcd», курсор после «ab», вставили «123456».
      final result = _apply(6, 'abcd', 'ab123456cd', cursor: 8);
      expect(result.text, 'ab12cd');
      expect(result.selection.baseOffset, 4);
    });

    test('эмодзи (суррогатная пара) считается одним символом', () {
      final text = _smile * 3;
      expect(_apply(3, '', text).text, text);
    });

    test('обрезка на границе суррогатной пары не рвёт пару', () {
      // Лимит 3: «ab» + два эмодзи. Помещается «ab» + один эмодзи целиком.
      final result = _apply(3, 'ab', 'ab$_smile$_smile');
      expect(result.text, 'ab$_smile');
      expect(result.text.length, 4);
      expect(result.text.runes.last, 0x1F600);
    });

    test('лимит посреди пары: остаётся только целая кодовая точка', () {
      // Лимит 1: один эмодзи (2 единицы UTF-16), а не его половинка.
      final result = _apply(1, '', '$_smile$_smile');
      expect(result.text, _smile);
    });

    test('флаг — две кодовые точки: помещается ровно при лимите 2', () {
      expect(_apply(2, '', _flag).text, _flag);
      expect(_apply(2, _flag, [_flag, 'a'].join()).text, _flag);
    });

    test('семья — пять кодовых точек, как считает domain', () {
      expect(_apply(5, '', _family).text, _family);
      // 'a' + семья = 6 точек: при лимите 5 остаются 'a' и первые 4 точки.
      final result = _apply(5, 'a', 'a$_family');
      expect(runesLength(result.text), 5);
      expect(result.text, 'a${String.fromCharCodes(_family.runes.take(4))}');
    });

    test('лимит 200: русский текст и составной эмодзи', () {
      final ru200 = List.filled(200, 'я').join();
      expect(_apply(200, ru200, '$ru200я').text, ru200);
      final families = List.filled(40, _family).join();
      expect(runesLength(families), 200);
      expect(_apply(200, families, '$families$_family').text, families);
    });

    test('лимит 0 не пускает ничего', () {
      expect(_apply(0, '', 'a').text, '');
    });

    test('без действительного курсора обрезает хвост', () {
      final result = RunesLengthFormatter(3).formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: 'abcdef'),
      );
      expect(result.text, 'abc');
    });
  });
}
