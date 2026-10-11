import 'package:flutter/foundation.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// Разделы вкладки «Аналитика» (ADR 0012, п. 1). Порядок — как в строке
/// разделов слева направо.
enum AnalyticsSection { categories, dynamics, comparison, operations }

/// Выбранный период экрана «Аналитика»: вид (день, неделя, месяц, год) и
/// сдвиг назад/вперёд. Только в памяти, про виджеты и `lib/app` не знает
/// (ADR 0002); «сегодня» передаётся снаружи, часы не читаются.
///
/// Слушатели уведомляются один раз на настоящее изменение и ни разу на
/// «пустое» действие. Правила сдвига — функции `analytics_period.dart`.
class AnalyticsController extends ChangeNotifier {
  AnalyticsController({
    required DateOnly today,
    DateOnly? firstDay,
    this._firstDayKnown = true,
  }) : _today = today,
       _period = currentPeriod(PeriodKind.month, today) {
    _firstDay = firstDay;
  }

  DateOnly _today;
  DateOnly? _firstDay;
  bool _firstDayKnown;
  AnalyticsPeriod _period;
  TransactionType _type = TransactionType.expense;

  AnalyticsSection _section = AnalyticsSection.categories;
  String? _categoryId;

  AnalyticsPeriod get period => _period;

  /// Выбранный раздел вкладки; по умолчанию «Категории». Только в памяти,
  /// от периода и типа не зависит.
  AnalyticsSection get section => _section;

  /// Выбирает раздел. Тот же раздел — ничего не делает.
  void selectSection(AnalyticsSection section) {
    if (section == _section) return;
    _section = section;
    notifyListeners();
  }

  /// Какие операции показывают кольцо и список категорий; по умолчанию расходы.
  /// Не зависит от периода: при смене периода остаётся прежним.
  TransactionType get type => _type;

  /// Сегодняшний день; обновляется через [updateToday].
  DateOnly get today => _today;

  /// День самой ранней операции; `null` — операций нет или ещё неизвестно.
  DateOnly? get firstDay => _firstDay;

  /// false — ответа базы о первой операции ещё не было.
  bool get firstDayKnown => _firstDayKnown;

  /// Назад можно до периода, в который попадает первая операция. Без первого
  /// дня — нельзя.
  bool get canGoBack {
    final first = _firstDay;
    final previous = previousPeriod(_period);
    return first != null && previous != null && previous.range.end >= first;
  }

  /// Вперёд можно не дальше текущего периода своего вида; когда точно известно,
  /// что операций нет, стрелок нет.
  bool get canGoForward =>
      (!_firstDayKnown || _firstDay != null) &&
      nextPeriod(_period, _today) != null;

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

  /// Категория, выбранная фильтром в «Динамике»; `null` — все категории.
  /// Только в памяти; сбрасывается при смене типа и вместе с контроллером при
  /// «Очистить всё».
  String? get categoryId => _categoryId;

  /// Выбирает категорию фильтра «Динамики». То же значение — ничего не делает.
  void selectCategory(String? categoryId) {
    if (categoryId == _categoryId) return;
    _categoryId = categoryId;
    notifyListeners();
  }

  /// Выбирает тип операций для кольца и списка. Тот же тип — ничего не делает.
  /// Новый тип сбрасывает фильтр категории: у доходов и расходов категории
  /// разные.
  void selectType(TransactionType type) {
    if (type == _type) return;
    _type = type;
    _categoryId = null;
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
  /// [known] false — база ещё не ответила (тогда null значит «неизвестно»).
  void updateFirstDay(DateOnly? day, {bool known = true}) {
    if (day == _firstDay && known == _firstDayKnown) return;
    _firstDay = day;
    _firstDayKnown = known;
    notifyListeners();
  }
}
