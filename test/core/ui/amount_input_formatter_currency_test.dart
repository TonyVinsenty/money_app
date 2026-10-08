import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/amount_input_formatter.dart';

TextEditingValue _v(String text) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: text.length),
);

void main() {
  test('8 знаков: восьмая цифра проходит, девятая отклоняется', () {
    const formatter = AmountInputFormatter(maxDecimals: 8);
    final eight = formatter.formatEditUpdate(_v(''), _v('0,12345678'));
    expect(eight.text, '0,12345678');
    final nine = formatter.formatEditUpdate(eight, _v('0,123456789'));
    expect(nine.text, '0,12345678');
  });

  test('0 знаков: запятая и точка не вводятся', () {
    const formatter = AmountInputFormatter(maxDecimals: 0);
    final one = formatter.formatEditUpdate(_v(''), _v('1'));
    expect(formatter.formatEditUpdate(one, _v('1,')).text, '1');
    expect(formatter.formatEditUpdate(one, _v('1.')).text, '1');
    expect(formatter.formatEditUpdate(_v(''), _v('1,5')).text, '');
    expect(formatter.formatEditUpdate(one, _v('15')).text, '15');
  });

  test('по умолчанию 2 знака, как раньше', () {
    const formatter = AmountInputFormatter();
    final two = formatter.formatEditUpdate(_v(''), _v('1,25'));
    expect(formatter.formatEditUpdate(two, _v('1,256')).text, '1,25');
  });
}
