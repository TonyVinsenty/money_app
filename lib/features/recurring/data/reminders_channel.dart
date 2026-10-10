import 'package:flutter/services.dart';
import 'package:money_app/features/recurring/domain/reminder_plan.dart';

/// Имя канала к нативному коду (Swift и Kotlin пишутся в шагах 6.24-6.25).
const remindersChannelName = 'com.tonyvinsenty.zuno/reminders';

/// Имена методов канала; нативный код читает их под такими же именами.
const remindersRequestPermissionMethod = 'requestPermission';
const remindersPermissionStatusMethod = 'permissionStatus';
const remindersReplaceAllMethod = 'replaceAll';

/// Состояние разрешения на уведомления (ответ `permissionStatus`:
/// строки `granted`, `denied`, `notDetermined`).
enum ReminderPermission { granted, denied, notDetermined }

/// Вызов метода канала: имя и аргументы -> ответ. В приложении это
/// [MethodChannel.invokeMethod], в тестах - фейк.
typedef RemindersInvoke = Future<Object?> Function(
  String method, [
  Object? arguments,
]);

Future<Object?> _platformInvoke(String method, [Object? arguments]) =>
    const MethodChannel(remindersChannelName)
        .invokeMethod<Object?>(method, arguments);

/// Обёртка канала напоминаний. Ошибка нативной стороны приходит как
/// [PlatformException]; `null` вместо ответа (платформа без реализации)
/// считается отказом.
class RemindersChannel {
  const RemindersChannel({this._invoke = _platformInvoke});

  final RemindersInvoke _invoke;

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
