import 'package:money_app/core/format/percent_format.dart';
import 'package:money_app/core/ui/category_labels.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/history_view.dart';

/// Запасное имя счёта в полоске, если его нет среди известных счетов.
const String historyUnknownAccount = 'не найден';

/// Подпись полоски фильтра: «Фильтр: Расходы · Продукты», «Фильтр: Доходы»,
/// «Фильтр: Расходы · 3 категории», «Фильтр: Расходы · Кафе · Счёт: Карта».
///
/// Одна-две категории называются по именам (из [categories], архивные тоже),
/// три и больше — числом. Набор `null` («все категории») в подпись не входит.
/// Счёт называется по [accountName] (архивный тоже); неизвестный -
/// [historyUnknownAccount]. Для выключенного фильтра подпись не нужна, но
/// функция вернёт «Фильтр: Все».
String historyFilterLabel(
  HistoryFilter filter,
  Iterable<Category> categories, {
  String? accountName,
}) {
  final expense = filter.expenseCategoryIds;
  final income = filter.incomeCategoryIds;
  final account = filter.accountId == null
      ? null
      : 'Счёт: ${accountName ?? historyUnknownAccount}';

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
      final hasSets = expense != null || income != null;
      final parts = [
        if (hasSets || account == null) 'Все',
        if (expense != null) 'расходы: ${_describe(expense, categories)}',
        if (income != null) 'доходы: ${_describe(income, categories)}',
        ?account,
      ];
      return 'Фильтр: ${parts.join(' · ')}';
  }

  final parts = [
    typeLabel,
    if (ids != null) _describe(ids, categories),
    ?account,
  ];
  return 'Фильтр: ${parts.join(' · ')}';
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
  Iterable<Category> categories, {
  String? accountName,
}) {
  if (!filter.isActive) return 'Фильтр';
  const prefix = 'Фильтр: ';
  final body = historyFilterLabel(
    filter,
    categories,
    accountName: accountName,
  ).substring(prefix.length).replaceAll(' · ', ', ');
  return 'Фильтр, включён: ${body[0].toLowerCase()}${body.substring(1)}';
}
