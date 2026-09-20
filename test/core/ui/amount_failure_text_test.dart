import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/currency.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/money/parse_amount.dart';
import 'package:money_app/core/ui/amount_failure_text.dart';

/// Неразрывный пробел задаём кодом, а не литералом, чтобы его было видно.
final String nbsp = String.fromCharCode(0x00A0);

void main() {
  group('amountFailureMessage', () {
    test('для каждой причины есть непустой текст', () {
      for (final failure in AmountParseFailure.values) {
        expect(
          amountFailureMessage(failure).trim(),
          isNotEmpty,
          reason: '$failure',
        );
      }
    });

    test('тексты у разных причин различаются', () {
      final messages = AmountParseFailure.values
          .map(amountFailureMessage)
          .toSet();
      expect(messages, hasLength(AmountParseFailure.values.length));
    });

    test('в текстах нет технических слов Exception и Error', () {
      for (final failure in AmountParseFailure.values) {
        final message = amountFailureMessage(failure);
        expect(message, isNot(contains('Exception')), reason: '$failure');
        expect(message, isNot(contains('Error')), reason: '$failure');
      }
    });

    test('точные строки для всех шести причин', () {
      expect(amountFailureMessage(AmountParseFailure.empty), 'Введите сумму');
      expect(
        amountFailureMessage(AmountParseFailure.notANumber),
        'Введите сумму цифрами. Пример: 1${nbsp}234,56',
      );
      expect(
        amountFailureMessage(AmountParseFailure.negative),
        'Знак не нужен: доход это или расход, зависит от нажатой кнопки',
      );
      expect(
        amountFailureMessage(AmountParseFailure.tooManyDecimals),
        'После запятой или точки — не больше двух цифр. '
        'Тысячи пишите без точки: 1234',
      );
      expect(
        amountFailureMessage(AmountParseFailure.tooManySeparators),
        'Слишком много запятых или точек. Пример: 1${nbsp}234,56',
      );
      expect(
        amountFailureMessage(AmountParseFailure.tooLarge),
        'Слишком большая сумма (не больше '
        '1${nbsp}000${nbsp}000${nbsp}000${nbsp}000,00$nbsp₽)',
      );
    });

    test('в примере «1 234,56» стоит неразрывный пробел, обычного нет', () {
      for (final failure in [
        AmountParseFailure.notANumber,
        AmountParseFailure.tooManySeparators,
      ]) {
        final message = amountFailureMessage(failure);
        expect(message, contains('1${nbsp}234,56'), reason: '$failure');
        expect(message, isNot(contains('1 234')), reason: '$failure');
      }
    });

    test('в предельной сумме и перед ₽ только неразрывные пробелы', () {
      final message = amountFailureMessage(AmountParseFailure.tooLarge);
      expect(message, contains('1${nbsp}000${nbsp}000'));
      expect(message, contains('$nbsp₽'));
      expect(message, isNot(contains('000 000')));
      expect(message, isNot(contains(' ₽')));
    });

    test('текст tooLarge содержит предел из maxInputMajorUnits', () {
      final limit = formatMoney(
        Money.fromMajorParts(maxInputMajorUnits, 0, rubCurrencyCode),
      );
      expect(
        amountFailureMessage(AmountParseFailure.tooLarge),
        contains(limit),
      );
    });

    test('предел сейчас — 1 000 000 000 000,00 ₽ с неразрывными пробелами', () {
      expect(
        amountFailureMessage(AmountParseFailure.tooLarge),
        contains('1${nbsp}000${nbsp}000${nbsp}000${nbsp}000,00$nbsp₽'),
      );
    });

    test('текст tooManyDecimals подсказывает писать тысячи как 1234', () {
      expect(
        amountFailureMessage(AmountParseFailure.tooManyDecimals),
        contains('1234'),
      );
    });
  });
}
