import 'package:flutter/material.dart';

/// Убирает висящее сообщение внизу (SnackBar), когда открывается новый экран.
///
/// Зачем: сообщение живёт на общем `ScaffoldMessenger` и переезжает на
/// следующий экран. После «В архив» «Вернуть» висит 6 секунд и закрывало
/// кнопку «В архив» в следующей открытой форме. Открыв другой экран, человек
/// уже ушёл дальше, и «Отменить» к нему не относится.
///
/// Диалоги и листы снизу (не `PageRoute`) сообщение не трогают: они
/// открываются поверх того же экрана.
class SnackBarDismissObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // Первый экран приложения: убирать ещё нечего.
    if (route is! PageRoute || previousRoute == null) return;
    final context = navigator?.context;
    if (context == null) return;
    ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
  }
}
