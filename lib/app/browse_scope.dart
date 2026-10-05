import 'dart:async';

import 'package:flutter/material.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/app_services.dart';
import 'package:money_app/app/browse_controller.dart';
import 'package:money_app/core/time/date_only.dart';

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
    required super.child,
    super.key,
  }) : super(notifier: controller);

  /// Номер выбранной вкладки нижней навигации.
  final ValueNotifier<int> selectedTab;

  /// Контроллер ближайшего [BrowseScope]; виджет зависит от его изменений.
  static BrowseController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<BrowseScope>();
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

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        final services = _services;
        if (services != null) _controller?.updateToday(services.clock.today());
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
    _services = services;
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _subscription?.cancel();
    _controller?.dispose();
    _selectedTab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BrowseScope(
      controller: _controller!,
      selectedTab: _selectedTab,
      child: widget.child,
    );
  }
}
