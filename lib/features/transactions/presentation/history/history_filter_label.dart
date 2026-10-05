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
      final parts = [
        'Все',
        if (expense != null) 'расходы: ${_describe(expense, categories)}',
        if (income != null) 'доходы: ${_describe(income, categories)}',
      ];
      return 'Фильтр: ${parts.join(' · ')}';
  }

  if (ids == null) return 'Фильтр: $typeLabel';
  return 'Фильтр: $typeLabel · ${_describe(ids, categories)}';
}

/// «нет категорий», «Продукты, Кафе» или «3 категории».
String _describe(Set<String> ids, Iterable<Category> categories) {
  if (ids.isEmpty) return 'нет категорий';
  if (ids.length >= 3) {
    final n = ids.length;
    return '$n ${pluralRu(n, 'категория', 'категории', 'категорий')}';
  }
  final byId = {for (final c in categories) c.id: c.name};
  return [for (final id in ids) byId[id] ?? noCategoryLabel].join(', ');
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
