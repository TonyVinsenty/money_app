import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:money_app/app/app_tab_indices.dart';
import 'package:money_app/app/browse_scope.dart';
import 'package:money_app/features/recurring/data/reminders_channel.dart';

/// Тап по уведомлению о платеже открывает вкладку «Баланс» на «К оплате»
/// (ADR 0013, п. 11). Натив только запоминает тап; хост спрашивает про него
/// при запуске, при каждом возврате в приложение и по сигналу `openDue`.
/// Ставится под `BrowseHost`: переключает его вкладку.
class NotificationOpenHost extends StatefulWidget {
  const NotificationOpenHost({
    required this.channel,
    required this.child,
    super.key,
  });

  final RemindersChannel channel;
  final Widget child;

  /// Просьба прокрутить «Баланс» к «К оплате»: `true`, пока вкладка её не
  /// выполнила (вкладка сама сбрасывает флаг). Без хоста - `null`.
  static ValueNotifier<bool>? revealDueOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_RevealDueScope>()?.request;

  @override
  State<NotificationOpenHost> createState() => _NotificationOpenHostState();
}

class _NotificationOpenHostState extends State<NotificationOpenHost> {
  final _revealDue = ValueNotifier(false);
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _ask);
    widget.channel.listenOpenDue(_ask);
    // Холодный запуск тапом: база уже открыта (хост живёт под ней).
    WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
  }

  @override
  void dispose() {
    widget.channel.listenOpenDue(null);
    _lifecycle.dispose();
    _revealDue.dispose();
    super.dispose();
  }

  // Двойного перехода нет: натив отвечает `true` только на первый вопрос
  // после тапа.
  void _ask() => unawaited(_askAsync());

  Future<void> _askAsync() async {
    try {
      if (!await widget.channel.takeOpenRequest() || !mounted) return;
      BrowseScope.selectedTabOf(context).value = balanceTabIndex;
      _revealDue.value = true;
    } on Object catch (error) {
      debugPrint('Тап по уведомлению: $error');
    }
  }

  @override
  Widget build(BuildContext context) =>
      _RevealDueScope(request: _revealDue, child: widget.child);
}

class _RevealDueScope extends InheritedWidget {
  const _RevealDueScope({required this.request, required super.child});

  final ValueNotifier<bool> request;

  @override
  bool updateShouldNotify(_RevealDueScope oldWidget) =>
      request != oldWidget.request;
}
