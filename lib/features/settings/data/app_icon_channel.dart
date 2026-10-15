import 'package:flutter/services.dart';
import 'package:money_app/features/settings/domain/app_icon_choice.dart';

/// Канал к нативному коду (ADR 0014, п. 2; `MainActivity.kt` и
/// `AppDelegate.swift`): какая иконка стоит и смена иконки.
const appIconChannelName = 'com.tonyvinsenty.zuno/app_icon';

/// Имена методов и ключ аргумента; нативный код читает их под такими же
/// именами.
const appIconCurrentMethod = 'current';
const appIconSetMethod = 'set';
const appIconSupportedMethod = 'supported';
const appIconIdArg = 'id';

/// Вызов метода канала: имя и аргументы -> ответ. В приложении это
/// [MethodChannel.invokeMethod], в тестах — фейк.
typedef AppIconInvoke = Future<Object?> Function(
  String method, [
  Object? arguments,
]);

Future<Object?> _platformInvoke(String method, [Object? arguments]) =>
    const MethodChannel(appIconChannelName)
        .invokeMethod<Object?>(method, arguments);

/// Обёртка канала иконки. Источник истины — система (ADR 0014, п. 1): выбор
/// нигде не хранится, каждый раз спрашиваем. Ошибка натива или отсутствие
/// канала (платформа без реализации, тесты) — «не поддерживается» и отказ,
/// без исключений.
class AppIconChannel {
  const AppIconChannel({this._invoke = _platformInvoke});

  final AppIconInvoke _invoke;

  /// Умеет ли система менять иконку.
  Future<bool> supported() async => await _call(appIconSupportedMethod) == true;

  /// Какая иконка стоит сейчас; `null` — узнать не удалось.
  Future<AppIconChoice?> current() async {
    final id = await _call(appIconCurrentMethod);
    return id is String ? AppIconChoice.fromId(id) : null;
  }

  /// Меняет иконку; `true` — система согласилась.
  Future<bool> set(AppIconChoice choice) async =>
      await _call(appIconSetMethod, {appIconIdArg: choice.id}) == true;

  Future<Object?> _call(String method, [Object? arguments]) async {
    try {
      return await _invoke(method, arguments);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
