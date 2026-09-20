import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/clock.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/occurrence.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';

/// Собирает обновлённую операцию для экрана правки.
///
/// Не меняются: `id`, тип и подкатегория (пока категория та же). Остальное:
/// - [amount] и [note] берутся из полей (комментарий нормализует сама
///   [Transaction]: пробелы по краям, пустой становится `null`);
/// - [day]: если он равен дню операции, день и момент остаются как были
///   (иначе правка суммы стирала бы время суток). Если день сменили, обе
///   величины выводятся заново из [day] и [clock] через [Occurrence.onDay],
///   как при создании: они всегда согласованы;
/// - [newCategory]: `null` или та же категория — категория и подкатегория
///   остаются; другая — подкатегория сбрасывается в `null` (старая
///   подкатегория принадлежит старой категории). Связь категории с типом
///   проверяет [Transaction.withCategory].
///
/// `createdAt` и `updatedAt` тут не участвуют: их ведёт репозиторий.
Transaction buildEditedTransaction({
  required Transaction original,
  required Money amount,
  required DateOnly day,
  required Clock clock,
  required String? note,
  Category? newCategory,
}) {
  var result = original.copyWith(amount: amount);
  if (day != original.occurredOn) {
    final occurrence = Occurrence.onDay(day, clock: clock);
    result = result.copyWith(
      occurredOn: occurrence.occurredOn,
      occurredAt: occurrence.occurredAt,
    );
  }
  if (newCategory != null && newCategory.id != original.categoryId) {
    result = result.withCategory(type: original.type, category: newCategory);
  }
  return result.withNote(note);
}
