import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/occurrence.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_rules.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Собирает обновлённую операцию для экрана правки.
///
/// Не меняется `id`; подкатегория остаётся, пока категория та же. Остальное:
/// - [newType]: `null` или тот же тип — ничего не сбрасывается. Другой тип:
///   категория и подкатегория сбрасываются, обязателен [newCategory] нового
///   вида; без него — [TransactionRuleException] с
///   [TransactionRule.emptyCategoryId], с категорией другого вида —
///   [TransactionRule.typeKindMismatch] (проверяет [Transaction.withCategory]);
/// - [amount] и [note] берутся из полей (комментарий нормализует сама
///   [Transaction]: пробелы по краям, пустой становится `null`);
/// - [day]: если он равен дню операции, день и момент остаются как были
///   (иначе правка суммы стирала бы время суток). Если день сменили, обе
///   величины выводятся заново из [day] и [clock] через [Occurrence.onDay],
///   как при создании: они всегда согласованы;
/// - [newCategory]: `null` или та же категория — категория и подкатегория
///   остаются; другая — подкатегория сбрасывается в `null` (старая
///   подкатегория принадлежит старой категории). Связь категории с типом
///   проверяет [Transaction.withCategory];
/// - [newSubcategory] применяется последней, к уже итоговой категории: её
///   родитель обязан быть равен категории операции, иначе
///   [TransactionRule.subcategoryNotOfCategory] ([Transaction.withSubcategory]);
/// - [clearSubcategory]: `true` снимает подкатегорию («Без подкатегории»).
///   Если задана и [newSubcategory], побеждает [newSubcategory].
///
/// `createdAt` и `updatedAt` тут не участвуют: их ведёт репозиторий.
Transaction buildEditedTransaction({
  required Transaction original,
  required Money amount,
  required DateOnly day,
  required Clock clock,
  required String? note,
  Category? newCategory,
  TransactionType? newType,
  Category? newSubcategory,
  bool clearSubcategory = false,
}) {
  final typeChanged = newType != null && newType != original.type;
  if (typeChanged && newCategory == null) {
    // У доходов и расходов разные наборы категорий: старая категория не
    // подходит, а «тихо» оставить её или пустую нельзя.
    throw TransactionRuleException(TransactionRule.emptyCategoryId);
  }
  var result = original.copyWith(amount: amount);
  if (day != original.occurredOn) {
    final occurrence = Occurrence.onDay(day, clock: clock);
    result = result.copyWith(
      occurredOn: occurrence.occurredOn,
      occurredAt: occurrence.occurredAt,
    );
  }
  if (typeChanged) {
    // Тип и категория меняются вместе; подкатегория сбрасывается.
    result = result.withCategory(type: newType, category: newCategory!);
  } else if (newCategory != null && newCategory.id != original.categoryId) {
    result = result.withCategory(type: original.type, category: newCategory);
  }
  if (newSubcategory != null) {
    result = result.withSubcategory(newSubcategory);
  } else if (clearSubcategory) {
    result = result.withSubcategory(null);
  }
  return result.withNote(note);
}
