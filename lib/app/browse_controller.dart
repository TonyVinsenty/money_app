import 'package:flutter/foundation.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/transactions/domain/history_view.dart';

/// Что сейчас просматривает пользователь: выбранный месяц, фильтр и
/// сортировка «Истории» (ADR 0008). Общее для «Главной» и «Истории».
///
/// Только в памяти. Про виджеты не знает; «сегодня» передаётся снаружи
/// (его читает хост из `Clock`). Слушатели уведомляются один раз на
/// настоящее изменение и ни разу на «пустое» действие.
class BrowseController extends ChangeNotifier {
  BrowseController({required this.today}) : _month = monthRange(today);

  /// Сегодняшний день на момент создания контроллера.
  final DateOnly today;

  DateRange _month;
  DateOnly? _firstDay;
  HistoryFilter _historyFilter = HistoryFilter.off;
  HistorySort _historySort = HistorySort.newestFirst;

  /// Выбранный календарный месяц.
  DateRange get month => _month;

  /// День самой ранней «живой» операции; `null` — операций нет.
  DateOnly? get firstDay => _firstDay;

  HistoryFilter get historyFilter => _historyFilter;
  HistorySort get historySort => _historySort;

  /// Назад можно, пока выбранный месяц позже месяца первой операции.
  bool get canGoBack {
    final first = _firstDay;
    return first != null && _month.start > monthRange(first).start;
  }

  /// Вперёд можно не дальше текущего месяца.
  bool get canGoForward => _next() != null;

  void previousMonth() {
    if (!canGoBack) return;
    _setMonth(_previous().range);
  }

  void nextMonth() {
    final next = _next();
    if (next == null) return;
    _setMonth(next.range);
  }

  /// Показывает месяц дня [day]; будущее обрезается текущим месяцем.
  ///
  /// Раньше первой операции не запрещаем: операция в этом месяце могла
  /// только что появиться, а [updateFirstDay] придёт позже.
  void showMonthOf(DateOnly day) {
    _setMonth(monthRange(day > today ? today : day));
  }

  /// Новый день первой операции. Выбранный месяц не двигается, даже если
  /// оказался раньше (самую раннюю удалили): просто [canGoBack] станет false.
  void updateFirstDay(DateOnly? day) {
    if (day == _firstDay) return;
    _firstDay = day;
    notifyListeners();
  }

  void setHistoryFilter(HistoryFilter filter) {
    if (filter == _historyFilter) return;
    _historyFilter = filter;
    notifyListeners();
  }

  /// Выключает фильтр; сортировку не трогает.
  void resetHistoryFilter() => setHistoryFilter(HistoryFilter.off);

  void setHistorySort(HistorySort sort) {
    if (sort == _historySort) return;
    _historySort = sort;
    notifyListeners();
  }

  /// Фильтр «только расходы этих категорий»; месяц не меняет.
  void showCategoryExpenses(Set<String> ids) =>
      setHistoryFilter(HistoryFilter.expenseCategories(Set.of(ids)));

  AnalyticsPeriod get _asPeriod => AnalyticsPeriod(PeriodKind.month, _month);

  AnalyticsPeriod _previous() => previousPeriod(_asPeriod)!;

  AnalyticsPeriod? _next() => nextPeriod(_asPeriod, today);

  void _setMonth(DateRange month) {
    if (month == _month) return;
    _month = month;
    notifyListeners();
  }
}
