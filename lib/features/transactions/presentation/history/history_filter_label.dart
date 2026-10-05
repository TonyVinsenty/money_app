import 'package:money_app/core/format/percent_format.dart';
import 'package:money_app/core/ui/category_labels.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/history_view.dart';

/// Подпись полоски фильтра: «Фильтр: Расходы · Продукты», «Фильтр: Доходы»,
/// «Фильтр: Расходы · 3 категории».
///
/// Одна-две категории называются по именам (из [categories], архивные тоже),
/// три и больше — числом. Набор `null` («все категории») в подпись не входит.
/// Для выключенного фильтра подпись не нужна, но функция вернёт «Фильтр: Все».
String historyFilterLabel(HistoryFilter filter, Iterable<Category> categories) {
  final expense = filter.expenseCategoryIds;
  final income = filter.incomeCategoryIds;

  // Какие наборы категорий относятся к выбранному типу.
  final Set<String>? ids;
  final String typeLabel;
  switch (filter.type) {
    case HistoryTypeFilter.expense:
      typeLabel = 'Расходы';
      ids = expense;
    case HistoryTypeFilter.income:
      typeLabel = 'Доходы';
      ids = income;
    case HistoryTypeFilter.all:
      if (expense != null && income != null) {
        typeLabel = 'Расходы и доходы';
        ids = {...expense, ...income};
      } else if (expense != null) {
        typeLabel = 'Расходы';
        ids = expense;
      } else if (income != null) {
        typeLabel = 'Доходы';
        ids = income;
      } else {
        typeLabel = 'Все';
        ids = null;
      }
  }

  if (ids == null) return 'Фильтр: $typeLabel';
  if (ids.isEmpty) return 'Фильтр: $typeLabel · нет категорий';
  if (ids.length >= 3) {
    final n = ids.length;
    final word = pluralRu(n, 'категория', 'категории', 'категорий');
    return 'Фильтр: $typeLabel · $n $word';
  }
  final byId = {for (final c in categories) c.id: c.name};
  final names = [for (final id in ids) byId[id] ?? noCategoryLabel];
  return 'Фильтр: $typeLabel · ${names.join(', ')}';
}

/// Озвучка кнопки «Фильтр»: «Фильтр» или «Фильтр, включён: расходы, Продукты».
///
/// Берёт [historyFilterLabel] без слова «Фильтр:», разделитель «·» заменяет
/// запятой, а первую букву (тип) делает маленькой.
String historyFilterSpoken(
  HistoryFilter filter,
  Iterable<Category> categories,
) {
  if (!filter.isActive) return 'Фильтр';
  const prefix = 'Фильтр: ';
  final body = historyFilterLabel(
    filter,
    categories,
  ).substring(prefix.length).replaceAll(' · ', ', ');
  return 'Фильтр, включён: ${body[0].toLowerCase()}${body.substring(1)}';
}
