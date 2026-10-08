import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/parse_amount.dart';
import 'package:money_app/core/ui/amount_failure_text.dart';
import 'package:money_app/core/ui/amount_field.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';

final String _nbsp = String.fromCharCode(0x00A0);

Widget _host(AmountFieldController controller) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(
    body: Center(child: AmountField(controller: controller, isIncome: false)),
  ),
);

void main() {
  testWidgets('поле в BTC: символ BTC вместо рубля, озвучка, 8 знаков', (
    tester,
  ) async {
    final controller = AmountFieldController(currency: currencyInfoFor('BTC'));
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));

    expect(find.text('BTC'), findsOneWidget);
    expect(find.text('₽'), findsNothing);

    await tester.enterText(find.byType(TextField), '0,5');
    await tester.pump();
    expect(
      find.bySemanticsLabel(RegExp('Расход 0,5 биткоина')),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField), '0,123456789');
    await tester.pump();
    expect(controller.text.text, '0,5');
    await tester.enterText(find.byType(TextField), '0,12345678');
    await tester.pump();
    expect(controller.text.text, '0,12345678');
  });

  testWidgets('поле в JPY: запятая не вводится', (tester) async {
    final controller = AmountFieldController(currency: currencyInfoFor('JPY'));
    addTearDown(controller.dispose);
    await tester.pumpWidget(_host(controller));

    await tester.enterText(find.byType(TextField), '15,5');
    await tester.pump();
    expect(controller.text.text, '');
  });

  test('рубль по умолчанию', () {
    final controller = AmountFieldController();
    addTearDown(controller.dispose);
    expect(controller.currency.code, 'RUB');
  });

  group('тексты ошибок с валютой', () {
    final btc = currencyInfoFor('BTC');
    test('BTC', () {
      expect(
        amountFailureMessage(AmountParseFailure.tooManyDecimals, currency: btc),
        'Не больше 8 знаков после запятой',
      );
      expect(
        amountFailureMessage(AmountParseFailure.tooLarge, currency: btc),
        'Не больше 1${_nbsp}000${_nbsp}000,00${_nbsp}BTC',
      );
    });
    test('JPY без дробной части', () {
      expect(
        amountFailureMessage(
          AmountParseFailure.tooManyDecimals,
          currency: currencyInfoFor('JPY'),
        ),
        'В этой валюте нет дробной части: введите целое число',
      );
    });
    test('рублёвые тексты прежние', () {
      expect(
        amountFailureMessage(AmountParseFailure.tooManyDecimals),
        'После запятой или точки — не больше двух цифр. '
        'Тысячи пишите без точки: 1234',
      );
    });
  });
}
