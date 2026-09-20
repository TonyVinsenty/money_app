import 'package:drift/drift.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Превращает [TransactionType] в текст `'income'`/`'expense'` для колонки БД
/// и обратно.
///
/// Тексты записаны здесь явно, а не берутся из `name` enum: переименование
/// значения в коде не должно тихо менять формат хранения. Неизвестный текст
/// (в том числе пустой, `'INCOME'`, `'other'`) бросает [FormatException]
/// с самим значением, а не превращается в `null`.
class TransactionTypeConverter extends TypeConverter<TransactionType, String> {
  const TransactionTypeConverter();

  @override
  TransactionType fromSql(String fromDb) {
    switch (fromDb) {
      case 'income':
        return TransactionType.income;
      case 'expense':
        return TransactionType.expense;
      default:
        throw FormatException(
          'Bad TransactionType value in database: '
          '"$fromDb"',
        );
    }
  }

  @override
  String toSql(TransactionType value) {
    // Без default: при новом значении enum компилятор потребует добавить строку.
    switch (value) {
      case TransactionType.income:
        return 'income';
      case TransactionType.expense:
        return 'expense';
    }
  }
}
