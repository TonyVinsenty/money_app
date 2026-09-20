import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/money/parse_amount.dart';
import 'package:money_app/core/ui/amount_input_formatter.dart';

const _formatter = AmountInputFormatter();

/// Неразрывный пробел (U+00A0) собран из кода, а не набран.
final String _nbsp = String.fromCharCode(0x00A0);

/// В ожидаемых строках «_» обозначает разделитель разрядов (неразрывный пробел).
String _g(String text) => text.replaceAll('_', _nbsp);

/// Значение поля: [text] с курсором [cursor] (по умолчанию в конце).
TextEditingValue _value(String text, [int? cursor, int? extent]) {
  final base = cursor ?? text.length;
  return TextEditingValue(
    text: text,
    selection: TextSelection(baseOffset: base, extentOffset: extent ?? base),
  );
}

/// Пользователь заменил [oldValue] на [newText] с курсором [cursor].
TextEditingValue _edit(
  TextEditingValue oldValue,
  String newText, [
  int? cursor,
]) {
  return _formatter.formatEditUpdate(oldValue, _value(newText, cursor));
}

/// Печатает [chars] по одному символу в конец поля, начиная с пустого.
TextEditingValue _typeAll(String chars) {
  var current = TextEditingValue.empty;
  for (final char in chars.split('')) {
    current = _edit(current, current.text + char);
  }
  return current;
}

void _expectValue(TextEditingValue actual, String text, int cursor) {
  expect(actual.text, _g(text));
  expect(actual.selection.isCollapsed, isTrue);
  expect(actual.selection.baseOffset, cursor);
}

void main() {
  group('печать по одной цифре', () {
    test('короткое число остаётся как есть, курсор в конце', () {
      _expectValue(_typeAll('123'), '123', 3);
    });

    test('переход через тысячу: пробел появляется, курсор в конце', () {
      final result = _typeAll('1234');
      _expectValue(result, '1_234', 5);
    });

    test('12345 и 1234567 группируются по три', () {
      _expectValue(_typeAll('12345'), '12_345', 6);
      _expectValue(_typeAll('1234567'), '1_234_567', 9);
    });

    test('после запятой: «12 345,6» и «12 345,67»', () {
      _expectValue(_typeAll('12345,6'), '12_345,6', 8);
      _expectValue(_typeAll('12345,67'), '12_345,67', 9);
    });

    test('вся цепочка печати даёт корректные промежуточные значения', () {
      var current = TextEditingValue.empty;
      final steps = <String>[];
      for (final char in '1234567'.split('')) {
        current = _edit(current, current.text + char);
        steps.add(current.text);
      }
      expect(steps, [
        _g('1'),
        _g('12'),
        _g('123'),
        _g('1_234'),
        _g('12_345'),
        _g('123_456'),
        _g('1_234_567'),
      ]);
    });
  });

  group('допустимые символы', () {
    test('буква молча не печатается, прежний текст и курсор сохраняются', () {
      final old = _value(_g('1_234'));
      _expectValue(_edit(old, '${_g('1_234')}a'), '1_234', 5);
    });

    test('буква в пустое поле даёт пустое поле', () {
      final result = _edit(TextEditingValue.empty, 'x');
      expect(result.text, isEmpty);
      expect(result.selection.baseOffset, 0);
    });

    test('буква в середине: курсор остаётся на месте', () {
      final old = _value(_g('1_234'), 3); // после «12»
      // Человек напечатал «a» после «1 2»: курсор стал 4.
      _expectValue(_edit(old, '${_g('1_2')}a34', 4), '1_234', 3);
    });

    test('минус, валюта и прочее пропадают', () {
      _expectValue(_edit(TextEditingValue.empty, '-5 ₽'), '5', 1);
    });

    test('точка превращается в запятую', () {
      _expectValue(_typeAll('12.5'), '12,5', 4);
    });

    test('пробел любого вида не остаётся лишним', () {
      final mixed = '1 2${String.fromCharCode(0x202F)}3${_nbsp}4';
      _expectValue(_edit(TextEditingValue.empty, mixed), '1_234', 5);
    });
  });

  group('разделитель и дробная часть', () {
    test('второй разделитель отклоняется: возвращается прежнее значение', () {
      final old = _value('12,5');
      expect(_edit(old, '12,5,'), old);
      expect(_edit(old, '12,5.'), old);
    });

    test('точка после запятой тоже считается вторым разделителем', () {
      final old = _value('12,');
      expect(_edit(old, '12,.'), old);
    });

    test('третья цифра после запятой отклоняется', () {
      final old = _value(_g('1_234,56'));
      expect(_edit(old, '${_g('1_234,56')}7'), old);
    });

    test('цифра в середине дробной части, дающая три знака, отклоняется', () {
      final old = _value('1,25', 3);
      expect(_edit(old, '1,275', 4), old);
    });

    test('запятая в конце допустима', () {
      _expectValue(_typeAll('12,'), '12,', 3);
    });

    test('запятая первой становится «0,»', () {
      _expectValue(_typeAll(','), '0,', 2);
    });

    test('«,5» становится «0,5»', () {
      _expectValue(_typeAll(',5'), '0,5', 3);
    });
  });

  group('ведущие нули', () {
    test('«0» допустим', () {
      _expectValue(_typeAll('0'), '0', 1);
    });

    test('«00» становится «0»', () {
      _expectValue(_typeAll('00'), '0', 1);
    });

    test('«007» становится «7»', () {
      _expectValue(_typeAll('007'), '7', 1);
      _expectValue(_edit(TextEditingValue.empty, '007'), '7', 1);
    });

    test('цифра после нуля заменяет его: «05» -> «5»', () {
      _expectValue(_typeAll('05'), '5', 1);
    });

    test('«0,05» остаётся', () {
      _expectValue(_typeAll('0,05'), '0,05', 4);
    });

    test('ноль и запятая: «0,» допустимо', () {
      _expectValue(_typeAll('0,'), '0,', 2);
    });
  });

  group('вставка из буфера', () {
    test('«1234567,89» группируется, курсор в конце', () {
      _expectValue(
        _edit(TextEditingValue.empty, '1234567,89'),
        '1_234_567,89',
        12,
      );
    });

    test('с мусором: «abc 12 345,6 руб» -> «12 345,6», курсор в конце', () {
      _expectValue(
        _edit(TextEditingValue.empty, 'abc 12 345,6 руб'),
        '12_345,6',
        8,
      );
    });

    test('вставка в середину: курсор сразу за вставленным', () {
      // Было «1 234», курсор после «1»; вставили «99»: «199 234», курсор 4.
      final old = _value(_g('1_234'), 1);
      _expectValue(_edit(old, '199${_g('_234')}', 3), '199_234', 3);
    });

    test('вставка с двумя разделителями отклоняется', () {
      final old = _value('5');
      expect(_edit(old, '1.234.567'), old);
    });

    test('вставка с тремя знаками после запятой отклоняется', () {
      final old = _value('5');
      expect(_edit(old, '1,234'), old);
    });

    test('вставка поверх выделения заменяет его', () {
      final old = _value(_g('1_234'), 0, 5); // всё выделено
      _expectValue(_edit(old, '77', 2), '77', 2);
    });

    test('выделение сохраняет направление и обе границы', () {
      final result = _formatter.formatEditUpdate(
        _value('1234'),
        TextEditingValue(
          text: '12345',
          selection: const TextSelection(baseOffset: 5, extentOffset: 1),
        ),
      );
      expect(result.text, _g('12_345'));
      expect(result.selection.baseOffset, 6);
      expect(result.selection.extentOffset, 1);
    });
  });

  group('удаление', () {
    test('удаление последней цифры: группа пересобирается, курсор в конце', () {
      final old = _value(_g('1_234'));
      _expectValue(_edit(old, _g('1_23')), '123', 3);
    });

    test('удаление в середине: курсор остаётся на месте', () {
      // «12 345», курсор после «123» (offset 5), backspace стирает «3».
      final old = _value(_g('12_345'), 5);
      _expectValue(_edit(old, _g('12_45'), 4), '1_245', 4);
    });

    test('удаление первой цифры: курсор остаётся в начале', () {
      final old = _value(_g('1_234'), 1);
      _expectValue(_edit(old, _g('_234'), 0), '234', 0);
    });

    test('backspace сразу за пробелом стирает цифру перед ним', () {
      // «1 234», курсор за пробелом (2), backspace.
      final old = _value(_g('1_234'), 2);
      _expectValue(_edit(old, '1234', 1), '234', 0);
    });

    test('delete перед пробелом стирает цифру после него', () {
      // «1 234», курсор перед пробелом (1), delete.
      final old = _value(_g('1_234'), 1);
      _expectValue(_edit(old, '1234', 1), '134', 1);
    });

    test('удаление всего даёт пустое поле', () {
      final result = _edit(_value('7'), '');
      expect(result.text, isEmpty);
      expect(result.selection.baseOffset, 0);
    });

    test('удаление запятой склеивает части', () {
      final old = _value('12,5', 3);
      _expectValue(_edit(old, '125', 2), '125', 2);
    });

    test('удаление нуля перед запятой даёт «0,5»', () {
      final old = _value('0,5', 1);
      _expectValue(_edit(old, ',5', 0), '0,5', 0);
    });
  });

  group('курсор в середине строки', () {
    test('цифра в середине: курсор за ней', () {
      // «1 234», курсор после «12» (3), печатаем «9» -> «12 934», курсор 4.
      final old = _value(_g('1_234'), 3);
      _expectValue(_edit(old, '${_g('1_2')}934', 4), '12_934', 4);
    });

    test('цифра в середине, вызвавшая новую группу, не прыгает в начало', () {
      // «123», курсор после «1»; печатаем «9» -> «1 923», курсор после «19».
      final old = _value('123', 1);
      _expectValue(_edit(old, '1923', 2), '1_923', 3);
    });

    test('цифра в начале: курсор за ней', () {
      final old = _value(_g('1_234'), 0);
      _expectValue(_edit(old, '9${_g('1_234')}', 1), '91_234', 1);
    });

    test('невалидное выделение: курсор в конце', () {
      final result = _formatter.formatEditUpdate(
        TextEditingValue.empty,
        const TextEditingValue(text: '1234'),
      );
      expect(result.text, _g('1_234'));
      expect(result.selection.baseOffset, 5);
    });
  });

  group('пустая строка и согласованность', () {
    test('пустая остаётся пустой', () {
      final result = _edit(TextEditingValue.empty, '');
      expect(result.text, isEmpty);
      expect(result.selection.baseOffset, 0);
    });

    test('разделитель разрядов совпадает с formatMoney', () {
      final shown = formatMoney(
        Money.fromMinor(123456, 'RUB'),
        withCurrencySymbol: false,
      );
      expect(shown, '1${_nbsp}234,56');
      // Уже отформатированный текст форматтер не меняет.
      expect(_edit(_value(''), shown).text, shown);
    });

    test('результат всегда разбирается parseAmount', () {
      const inputs = <String>[
        '0',
        '00',
        '007',
        ',5',
        '5,',
        '0,05',
        '12.5',
        '12345,67',
        'abc 12 345,6 руб',
        '  9 9 9 ',
        '1234567,89',
      ];
      for (final input in inputs) {
        final result = _typeAll(input);
        expect(result.text, isNotEmpty, reason: input);
        expect(
          parseAmount(result.text),
          isA<AmountParsed>().having(
            (r) => r.amount.currency,
            'currency',
            'RUB',
          ),
          reason: '"$input" -> "${result.text}"',
        );
      }
    });

    test('значение из буфера тоже разбирается parseAmount', () {
      for (final pasted in ['007', ',5', '1 234,5', '1.5', '12abc3']) {
        final result = _edit(TextEditingValue.empty, pasted);
        expect(parseAmount(result.text), isA<AmountParsed>(), reason: pasted);
      }
    });

    test(
      'сумма выше предела не режется форматтером (это дело parseAmount)',
      () {
        final result = _typeAll('1000000000001');
        expect(result.text, _g('1_000_000_000_001'));
        expect(
          parseAmount(result.text),
          isA<AmountParseFailed>().having(
            (r) => r.failure,
            'failure',
            AmountParseFailure.tooLarge,
          ),
        );
      },
    );
  });
}
