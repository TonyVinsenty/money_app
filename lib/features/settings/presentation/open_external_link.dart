import 'package:flutter/services.dart';

/// Канал к нативному коду Android и iOS (см. `MainActivity.kt` и
/// `AppDelegate.swift`): открыть страницу во внешнем браузере без пакета
/// `url_launcher` (шаг 8.0).
const linksChannel = MethodChannel('com.tonyvinsenty.zuno/links');

/// Имя метода канала; в `MainActivity.kt` и `AppDelegate.swift` такое же.
const openUrlMethod = 'openUrl';

/// Ключ аргумента с адресом; нативный код читает его под этим же именем.
const openUrlArg = 'url';

/// Открытие адреса во внешнем браузере. В приложении это [openExternalLink];
/// в тестах подменяется фейком. `true` — браузер открылся.
typedef OpenLink = Future<bool> Function(String url);

/// Открывает [url] (только `https`) во внешнем браузере. `false`, если
/// открыть не удалось: нет браузера, ошибка натива или платформа без
/// реализации.
Future<bool> openExternalLink(String url) async {
  try {
    return await linksChannel.invokeMethod<bool>(openUrlMethod, {
          openUrlArg: url,
        }) ==
        true;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
