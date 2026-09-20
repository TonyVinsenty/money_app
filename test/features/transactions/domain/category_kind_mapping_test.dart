import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/category_kind_mapping.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

void main() {
  test(
    'тип операции и вид категории соответствуют друг другу в обе стороны',
    () {
      for (final type in TransactionType.values) {
        expect(type.categoryKind.transactionType, type);
      }
      for (final kind in CategoryKind.values) {
        expect(kind.transactionType.categoryKind, kind);
      }
      expect(TransactionType.income.categoryKind, CategoryKind.income);
      expect(TransactionType.expense.categoryKind, CategoryKind.expense);
    },
  );
}
