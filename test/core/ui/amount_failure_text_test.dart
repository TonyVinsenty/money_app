import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/parse_amount.dart';
import 'package:money_app/core/ui/amount_failure_text.dart';

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

    test('точные формулировки', () {
      expect(amountFailureMessage(AmountParseFailure.empty), 'Введите сумму');
      expect(
        amountFailureMessage(AmountParseFailure.tooLarge),
        'Слишком большая сумма',
      );
    });
  });
}
