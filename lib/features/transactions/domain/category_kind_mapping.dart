import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Связь двух перечислений: какой тип операции подходит категории этого вида.
///
/// Лежит в `transactions`, а не в `categories`: фича операций знает о
/// категориях, но не наоборот.
extension CategoryKindTransactionType on CategoryKind {
  /// Тип операции, который допустим в категориях этого вида.
  TransactionType get transactionType {
    switch (this) {
      case CategoryKind.income:
        return TransactionType.income;
      case CategoryKind.expense:
        return TransactionType.expense;
    }
  }
}

/// Обратная связь: в каких категориях (по виду) можно вести операции типа.
extension TransactionTypeCategoryKind on TransactionType {
  /// Вид категорий, подходящий этому типу операции.
  CategoryKind get categoryKind {
    switch (this) {
      case TransactionType.income:
        return CategoryKind.income;
      case TransactionType.expense:
        return CategoryKind.expense;
    }
  }
}
