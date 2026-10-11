import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Прячет клавиатуру при смене экрана.
///
/// Зачем: на iPhone после скриншота в быстром вводе и «Назад» клавиатура редко,
/// но «зависает» и остаётся на всех экранах. Обычно её убирает сама система;
/// здесь страховка: при закрытии, удалении и открытии маршрута снимаем фокус и
/// явно просим систему скрыть клавиатуру.
///
/// Автофокус нового экрана не страдает: `didPush` вызывается до того, как новый
/// экран построен, а автофокус срабатывает позже и снова показывает клавиатуру.
class KeyboardDismissObserver extends NavigatorObserver {
  void _dismiss() {
    FocusManager.instance.primaryFocus?.unfocus();
    unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _dismiss();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _dismiss();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _dismiss();
}
