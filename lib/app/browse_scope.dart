import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/app_services.dart';
import 'package:money_app/app/app_tab_indices.dart';
import 'package:money_app/app/browse_controller.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/recurring/domain/recurring_repository.dart';

/// Раздаёт [BrowseController] (месяц, фильтр, сортировка) и уведомитель
/// выбранной вкладки всем виджетам ниже (ADR 0008).
///
/// Как [AppScope]: виджет, вызвавший [of], перестраивается при каждом
/// изменении контроллера. Уведомитель вкладки не меняется, поэтому
/// [selectedTabOf] от scope не зависит; слушать его можно через
/// `ValueListenableBuilder`. Создаёт и освобождает всё [BrowseHost].
class BrowseScope extends InheritedNotifier<BrowseController> {
  const BrowseScope({
    required BrowseController controller,
    required this.selectedTab,
    required this.dues,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// Номер выбранной вкладки нижней навигации.
  final ValueNotifier<int> selectedTab;

  /// Записи «К оплате»: один поток `watchDue` на плашку «Главной» и значок
  /// вкладки «Баланс».
  final ValueListenable<List<RecurringDue>> dues;

  /// Записи «К оплате» (без подписки на контроллер); слушать через
  /// `ValueListenableBuilder`.
  static ValueListenable<List<RecurringDue>> duesOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<BrowseScope>();
    if (scope == null) throw FlutterError(_notFound);
    return scope.dues;
  }

  /// Контроллер ближайшего [BrowseScope]; виджет зависит от его изменений.
  static BrowseController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<BrowseScope>();
    if (scope == null) throw FlutterError(_notFound);
    return scope.notifier!;
  }

  /// Контроллер без подписки на его изменения: для обработчиков нажатий.
  static BrowseController controllerOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<BrowseScope>();
    if (scope == null) throw FlutterError(_notFound);
    return scope.notifier!;
  }

  /// Уведомитель выбранной вкладки (без подписки на контроллер).
  static ValueNotifier<int> selectedTabOf(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<BrowseScope>();
    if (scope == null) throw FlutterError(_notFound);
    return scope.selectedTab;
  }

  static const _notFound =
      'BrowseScope не найден выше этого виджета в дереве. В приложении его '
      'ставит BrowseHost внутри MoneyApp; в тесте оберните виджет в BrowseHost.';
}

/// Хозяин [BrowseScope]: создаёт контроллер и уведомитель вкладки, передаёт
/// контроллеру день первой операции из `watchFirstDay` и всё освобождает.
class BrowseHost extends StatefulWidget {
  const BrowseHost({required this.child, super.key});

  final Widget child;

  @override
  State<BrowseHost> createState() => _BrowseHostState();
}

class _BrowseHostState extends State<BrowseHost> {
  final ValueNotifier<int> _selectedTab = ValueNotifier<int>(0);
  BrowseController? _controller;
  AppServices? _services;
  StreamSubscription<DateOnly?>? _subscription;
  late final AppLifecycleListener _lifecycle;
  int _previousTab = 0;

  // Уход с вкладки «История» на другую снимает временный фильтр (тап по
  // сектору). Переход в карточку операции вкладку не меняет.
  void _onTabChanged() {
    final tab = _selectedTab.value;
    if (_previousTab == historyTabIndex && tab != historyTabIndex) {
      _controller?.leaveHistory();
    }
    _previousTab = tab;
  }

  @override
  void initState() {
    super.initState();
    _selectedTab.addListener(_onTabChanged);
    _lifecycle = AppLifecycleListener(
      onResume: () {
        final services = _services;
        if (services == null) return;
        _controller?.updateToday(services.clock.today());
        _materializeIfDayChanged(services);
      },
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    // Начальное «сегодня» из Clock; дальше его обновляет onResume.
    _controller ??= BrowseController(today: services.clock.today());
    if (!identical(services.transactions, _services?.transactions)) {
      _subscription?.cancel();
      // Ошибку чтения не показываем: остаётся прежний день первой операции,
      // но «неизвестно» снимаем, чтобы экран не застрял на загрузке.
      _subscription = services.transactions.watchFirstDay().listen(
        _controller!.updateFirstDay,
        onError: (Object _) => _controller!.markFirstDayKnown(),
      );
    }
    // Основная валюта сменилась: ручной фильтр по счёту сбрасывается.
    final currency = services.settings.mainCurrencyCode;
    final previous = _currency;
    _currency = currency;
    if (previous != null && previous != currency) {
      _controller!.clearManualAccountFilter();
    }
    _services = services;
    _materializeIfDayChanged(services);
    if (!identical(services.recurring, _duesFor)) {
      _duesFor = services.recurring;
      unawaited(_duesSubscription?.cancel());
      _duesSubscription = services.recurring.watchDue().listen(
        (list) => _dues.value = list,
        onError: (Object e) => debugPrint('К оплате: $e'),
      );
    }
  }

  // Единственная подписка на watchDue: из неё берут плашка и значок.
  final ValueNotifier<List<RecurringDue>> _dues = ValueNotifier(const []);
  StreamSubscription<List<RecurringDue>>? _duesSubscription;
  RecurringRepository? _duesFor;

  // Записи «К оплате» (ADR 0011, п. 5): при запуске и при возврате в
  // приложение, если сменился день. Не ждём: первый кадр не задерживается.
  void _materializeIfDayChanged(AppServices services) {
    final today = services.clock.today();
    final repository = services.recurring;
    if (_materializedDay == today && identical(_materializedFor, repository)) {
      return;
    }
    _materializedDay = today;
    _materializedFor = repository;
    unawaited(_materialize(repository, today));
  }

  Future<void> _materialize(
    RecurringRepository repository,
    DateOnly day,
  ) async {
    try {
      await repository.materializeDue(day);
    } catch (error) {
      // Приложение не падает: «К оплате» догонится при следующем запуске.
      debugPrint('materializeDue failed: $error');
      if (_materializedDay == day) _materializedDay = null; // повторить
    }
  }

  DateOnly? _materializedDay;
  RecurringRepository? _materializedFor;

  String? _currency;

  @override
  void dispose() {
    _lifecycle.dispose();
    _selectedTab.removeListener(_onTabChanged);
    _subscription?.cancel();
    unawaited(_duesSubscription?.cancel());
    _controller?.dispose();
    _selectedTab.dispose();
    _dues.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BrowseScope(
      controller: _controller!,
      selectedTab: _selectedTab,
      dues: _dues,
      child: widget.child,
    );
  }
}
