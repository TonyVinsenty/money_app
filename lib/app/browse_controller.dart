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
  BrowseController({required DateOnly today})
    : _today = today,
      _month = monthRange(today);

  /// Сегодняшний день; обновляется через [updateToday].
  DateOnly get today => _today;
  DateOnly _today;

  DateRange _month;
  DateOnly? _firstDay;
  HistoryFilter _manualFilter = HistoryFilter.off;
  HistoryFilter? _temporaryFilter;
  HistorySort _historySort = HistorySort.newestFirst;

  /// Выбранный календарный месяц.
  DateRange get month => _month;

  /// День самой ранней «живой» операции; `null` — операций нет.
  DateOnly? get firstDay => _firstDay;

  /// Пришёл ли уже ответ про первый день (в том числе `null` — «операций
  /// нет»). До него `firstDay == null` значит «ещё неизвестно».
  bool get firstDayKnown => _firstDayKnown;
  bool _firstDayKnown = false;

  /// Действующий фильтр: временный (если есть), иначе ручной.
  HistoryFilter get historyFilter => _temporaryFilter ?? _manualFilter;

  /// Есть ли временный фильтр от тапа по сектору.
  bool get hasTemporaryFilter => _temporaryFilter != null;
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

  /// Новое «сегодня» (приложение пережило полночь). Если выбран был старый
  /// текущий месяц, переходим на новый текущий; прошлый месяц не трогаем.
  /// Слушатели уведомляются один раз, а при том же дне ни разу.
  void updateToday(DateOnly day) {
    if (day == _today) return;
    final wasCurrent = _month == monthRange(_today);
    _today = day;
    if (wasCurrent) _month = monthRange(day);
    notifyListeners();
  }

  /// Новый день первой операции. Выбранный месяц не двигается, даже если
  /// оказался раньше (самую раннюю удалили): просто [canGoBack] станет false.
  void updateFirstDay(DateOnly? day) {
    if (_firstDayKnown && day == _firstDay) return;
    _firstDayKnown = true;
    _firstDay = day;
    notifyListeners();
  }

  /// Чтение первого дня не удалось: «неизвестно» не должно висеть вечно
  /// (экран перестанет показывать загрузку, день остаётся прежним).
  void markFirstDayKnown() {
    if (_firstDayKnown) return;
    _firstDayKnown = true;
    notifyListeners();
  }

  /// Ручное изменение фильтра. Если был временный (тап по сектору), текущий
  /// фильтр становится ручным и сохраняется как обычно.
  void setHistoryFilter(HistoryFilter filter) {
    final hadTemporary = _temporaryFilter != null;
    if (filter == historyFilter && !hadTemporary) return;
    _manualFilter = filter;
    _temporaryFilter = null;
    notifyListeners();
  }

  /// Пользователь ушёл из «Истории» на другую вкладку: временный фильтр
  /// снимается, возвращается прежний ручной. Без временного ничего не делает.
  void leaveHistory() {
    if (_temporaryFilter == null) return;
    _temporaryFilter = null;
    notifyListeners();
  }

  /// Смена основной валюты: ручной фильтр по счёту сбрасывается (счёт мог быть
  /// в другой валюте), тип и категории остаются. Временный фильтр не трогает.
  void clearManualAccountFilter() {
    if (_manualFilter.accountFilter is AnyAccount) return;
    _manualFilter = _manualFilter.withAnyAccount();
    notifyListeners();
  }

  /// Выключает фильтр; сортировку не трогает.
  void resetHistoryFilter() => setHistoryFilter(HistoryFilter.off);

  /// Текст в поле поиска «Истории» как набран (с пробелами): поле при
  /// возврате на вкладку показывает его же. Живёт, пока его не очистят.
  String get historySearch => _historySearch;
  String _historySearch = '';

  /// Идёт ли поиск: в запросе есть что-то кроме пробелов. Тогда «История»
  /// показывает все месяцы, а выбранный месяц не меняется.
  bool get isSearchingHistory =>
      normalizeHistorySearch(_historySearch).isNotEmpty;

  void setHistorySearch(String text) {
    if (text == _historySearch) return;
    _historySearch = text;
    notifyListeners();
  }

  void setHistorySort(HistorySort sort) {
    if (sort == _historySort) return;
    _historySort = sort;
    notifyListeners();
  }

  /// Временный фильтр «только расходы этих категорий» (тап по сектору):
  /// лежит поверх ручного и снимается при уходе из «Истории». Месяц не
  /// меняет; повторный вызов заменяет прежний временный фильтр.
  void showCategoryExpenses(Set<String> ids) {
    final filter = HistoryFilter.expenseCategories(Set.of(ids));
    if (filter == historyFilter) return;
    _temporaryFilter = filter;
    notifyListeners();
  }

  /// Временный фильтр «операции этого счёта» (кнопка «Операции» на экране
  /// счёта): как [showCategoryExpenses], снимается при уходе из «Истории».
  void showAccountTransactions(String accountId) {
    final filter = HistoryFilter.account(accountId);
    if (filter == historyFilter) return;
    _temporaryFilter = filter;
    notifyListeners();
  }

  /// Счётчик «Очистить всё»: растёт при каждом [resetAfterEraseAll]. По его
  /// смене вкладка «Аналитика» создаёт свой контроллер заново.
  int get eraseGeneration => _eraseGeneration;
  int _eraseGeneration = 0;

  /// После «Очистить всё» всё как при запуске: текущий месяц, ручной и
  /// временный фильтры сняты (в них могли остаться id стёртых счёта и
  /// категорий), поиск пуст, сортировка по умолчанию. Один раз уведомляет.
  void resetAfterEraseAll() {
    _month = monthRange(_today);
    _manualFilter = HistoryFilter.off;
    _temporaryFilter = null;
    _historySearch = '';
    _historySort = HistorySort.newestFirst;
    _eraseGeneration++;
    notifyListeners();
  }

  AnalyticsPeriod get _asPeriod => AnalyticsPeriod(PeriodKind.month, _month);

  AnalyticsPeriod _previous() => previousPeriod(_asPeriod)!;

  AnalyticsPeriod? _next() => nextPeriod(_asPeriod, today);

  void _setMonth(DateRange month) {
    if (month == _month) return;
    _month = month;
    notifyListeners();
  }
}
