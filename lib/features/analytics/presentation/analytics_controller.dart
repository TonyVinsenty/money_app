import 'package:flutter/foundation.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Выбранный период экрана «Аналитика»: вид (день, неделя, месяц, год) и
/// сдвиг назад/вперёд. Только в памяти, про виджеты и `lib/app` не знает
/// (ADR 0002); «сегодня» передаётся снаружи, часы не читаются.
///
/// Слушатели уведомляются один раз на настоящее изменение и ни разу на
/// «пустое» действие. Правила сдвига — функции `analytics_period.dart`.
class AnalyticsController extends ChangeNotifier {
  AnalyticsController({required DateOnly today, DateOnly? firstDay})
    : _today = today,
      _period = currentPeriod(PeriodKind.month, today) {
    _firstDay = firstDay;
  }

  DateOnly _today;
  DateOnly? _firstDay;
  AnalyticsPeriod _period;
  TransactionType _type = TransactionType.expense;

  AnalyticsPeriod get period => _period;

  /// Какие операции показывают кольцо и список категорий; по умолчанию расходы.
  /// Не зависит от периода: при смене периода остаётся прежним.
  TransactionType get type => _type;

  /// Сегодняшний день; обновляется через [updateToday].
  DateOnly get today => _today;

  /// День самой ранней операции; `null` — операций нет или ещё неизвестно.
  DateOnly? get firstDay => _firstDay;

  /// Назад можно до периода, в который попадает первая операция. Без первого
  /// дня — нельзя.
  bool get canGoBack {
    final first = _firstDay;
    final previous = previousPeriod(_period);
    return first != null && previous != null && previous.range.end >= first;
  }

  /// Вперёд можно не дальше текущего периода своего вида.
  bool get canGoForward => nextPeriod(_period, _today) != null;

  void previous() {
    if (!canGoBack) return;
    _period = previousPeriod(_period)!;
    notifyListeners();
  }

  void next() {
    final next = nextPeriod(_period, _today);
    if (next == null) return;
    _period = next;
    notifyListeners();
  }

  /// Меняет вид периода (день, неделя, месяц, год) по правилам
  /// [switchKind]. Тот же вид — ничего не делает. Свой интервал сюда не
  /// подходит: [ArgumentError].
  void selectKind(PeriodKind kind) {
    if (kind == PeriodKind.custom) {
      throw ArgumentError.value(
        kind,
        'kind',
        'custom period is not selected by kind',
      );
    }
    if (kind == _period.kind) return;
    _period = switchKind(_period, kind, _today);
    notifyListeners();
  }

  /// Выбирает тип операций для кольца и списка. Тот же тип — ничего не делает.
  void selectType(TransactionType type) {
    if (type == _type) return;
    _type = type;
    notifyListeners();
  }

  /// Выбирает свой интервал от [start] до [end] включительно. Конец позже
  /// «сегодня» или раньше начала — [ArgumentError]. Тот же интервал —
  /// ничего не делает.
  void selectCustomRange(DateOnly start, DateOnly end) {
    final next = customPeriod(start, end, today: _today);
    if (next == _period) return;
    _period = next;
    notifyListeners();
  }

  /// Новое «сегодня» (приложение пережило полночь). Если выбран был текущий
  /// период своего вида для старого «сегодня», переходим на текущий период
  /// для нового; иначе период не меняется.
  void updateToday(DateOnly day) {
    if (day == _today) return;
    final kind = _period.kind;
    final wasCurrent =
        kind != PeriodKind.custom && _period == currentPeriod(kind, _today);
    _today = day;
    if (wasCurrent) _period = currentPeriod(kind, day);
    notifyListeners();
  }

  /// Новый день первой операции. Выбранный период не двигается.
  void updateFirstDay(DateOnly? day) {
    if (day == _firstDay) return;
    _firstDay = day;
    notifyListeners();
  }
}
