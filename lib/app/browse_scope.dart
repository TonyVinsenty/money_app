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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = AppScope.of(context);
    // «Сегодня» берётся из Clock один раз, при создании контроллера.
    _controller ??= BrowseController(today: services.clock.today());
    if (!identical(services.transactions, _services?.transactions)) {
      _subscription?.cancel();
      // Ошибку чтения игнорируем: остаётся прежний день первой операции.
      _subscription = services.transactions.watchFirstDay().listen(
        _controller!.updateFirstDay,
        onError: (Object _) {},
      );
    }
    _services = services;
  }

  @override
  void dispose() {
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
