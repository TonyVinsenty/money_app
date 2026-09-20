import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/database/converters/transaction_type_converter.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

void main() {
  const converter = TransactionTypeConverter();

  group('toSql', () {
    test('income и expense', () {
      expect(converter.toSql(TransactionType.income), 'income');
      expect(converter.toSql(TransactionType.expense), 'expense');
    });
  });

  group('fromSql', () {
    test('income и expense', () {
      expect(converter.fromSql('income'), TransactionType.income);
      expect(converter.fromSql('expense'), TransactionType.expense);
    });

    const garbage = <String>[
      '',
      ' ',
      'Income',
      'INCOME',
      'EXPENSE',
      ' income',
      'income ',
      'expense\n',
      'other',
      'transfer',
      '0',
    ];

    for (final value in garbage) {
      test('мусор "$value" даёт FormatException с этим значением', () {
        expect(
          () => converter.fromSql(value),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              allOf(contains('TransactionType'), contains('"$value"')),
            ),
          ),
        );
      });
    }
  });

  group('все значения enum', () {
    for (final type in TransactionType.values) {
      test('$type проходит туда-обратно', () {
        expect(converter.fromSql(converter.toSql(type)), type);
      });
    }

    test('строки в базе разные у разных значений', () {
      final sqlValues = TransactionType.values.map(converter.toSql).toSet();
      expect(sqlValues, hasLength(TransactionType.values.length));
    });
  });
}
