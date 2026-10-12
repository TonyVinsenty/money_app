import 'package:flutter/services.dart';
import 'package:money_app/features/recurring/domain/reminder_plan.dart';

/// Имя канала к нативному коду (Swift и Kotlin пишутся в шагах 6.24-6.25).
const remindersChannelName = 'com.tonyvinsenty.zuno/reminders';

/// Имена методов канала; нативный код читает их под такими же именами.
const remindersRequestPermissionMethod = 'requestPermission';
const remindersPermissionStatusMethod = 'permissionStatus';
const remindersReplaceAllMethod = 'replaceAll';

/// Был ли тап по нашему уведомлению с прошлого вопроса (ADR 0013, п. 11).
const remindersTakeOpenRequestMethod = 'takeOpenRequest';

/// Обратный вызов от натива: тап случился, пока приложение открыто.
const remindersOpenDueMethod = 'openDue';

/// Открыть настройки уведомлений Zuno в системе.
const remindersOpenSettingsMethod = 'openSettings';

/// Вызов метода канала: имя и аргументы -> ответ. В приложении это
/// [MethodChannel.invokeMethod], в тестах - фейк.
typedef RemindersInvoke = Future<Object?> Function(
  String method, [
  Object? arguments,
]);

/// Ставит (или снимает при `null`) обработчик вызовов от натива: получает имя
/// метода. В приложении это [MethodChannel.setMethodCallHandler], в тестах -
/// фейк.
typedef RemindersSetHandler = void Function(
  Future<void> Function(String method)? handler,
);

Future<Object?> _platformInvoke(String method, [Object? arguments]) =>
    const MethodChannel(remindersChannelName)
        .invokeMethod<Object?>(method, arguments);

void _platformSetHandler(Future<void> Function(String method)? handler) =>
    const MethodChannel(remindersChannelName).setMethodCallHandler(
      handler == null ? null : (call) => handler(call.method),
    );

/// Обёртка канала напоминаний. Ошибка нативной стороны приходит как
/// [PlatformException]; `null` вместо ответа (платформа без реализации)
/// считается отказом.
class RemindersChannel {
  const RemindersChannel({
    this._invoke = _platformInvoke,
    this._setHandler = _platformSetHandler,
  });

  final RemindersInvoke _invoke;
  final RemindersSetHandler _setHandler;

  /// `true` один раз на каждый тап по уведомлению: натив сбрасывает флаг при
  /// ответе. Платформа без реализации - `false`.
  Future<bool> takeOpenRequest() async {
    try {
      return await _invoke(remindersTakeOpenRequestMethod) == true;
    } on MissingPluginException {
      return false;
    }
  }

  /// Открывает настройки уведомлений Zuno в системе (кнопка под пояснением
  /// об отказе).
  Future<void> openSettings() async {
    await _invoke(remindersOpenSettingsMethod);
  }

  /// [onOpenDue] вызывается, когда натив сообщает о тапе при открытом
  /// приложении; `null` снимает обработчик.
  void listenOpenDue(VoidCallback? onOpenDue) => _setHandler(
    onOpenDue == null
        ? null
        : (method) async {
            if (method == remindersOpenDueMethod) onOpenDue();
          },
  );

  /// Показывает системный запрос разрешения; `true`, если разрешено.
  Future<bool> requestPermission() async =>
      await _invoke(remindersRequestPermissionMethod) == true;

  /// Текущее состояние разрешения без запроса.
  Future<ReminderPermission> permissionStatus() async {
    return switch (await _invoke(remindersPermissionStatusMethod)) {
      'granted' => ReminderPermission.granted,
      'denied' => ReminderPermission.denied,
      _ => ReminderPermission.notDetermined,
    };
  }

  /// Снимает все свои запланированные уведомления и ставит [items] заново.
  /// Аргумент - список словарей [ReminderItem.toMap].
  Future<void> replaceAll(List<ReminderItem> items) async {
    await _invoke(remindersReplaceAllMethod, [
      for (final item in items) item.toMap(),
    ]);
  }
}
