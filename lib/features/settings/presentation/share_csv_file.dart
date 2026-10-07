import 'package:flutter/services.dart';

/// Канал к нативному коду Android и iOS (см. `MainActivity.kt` и
/// `AppDelegate.swift`).
///
/// Через него файл уходит в системное «Поделиться» без пакета `share_plus`:
/// окно открывается из приложения, а выбранное приложение (например,
/// Telegram) не остаётся внутри окна Zuno.
const shareChannel = MethodChannel('com.tonyvinsenty.zuno/share');

/// Имя метода канала; в `MainActivity.kt` и `AppDelegate.swift` такое же.
const shareCsvFileMethod = 'shareCsvFile';

/// Ключ аргумента с путём к файлу; нативный код читает его под этим же именем.
const shareCsvFilePathArg = 'path';

/// Отправка готового файла наружу по пути [path].
///
/// В приложении это системное «Поделиться» ([shareCsvFile]); в тестах
/// подменяется фейком, чтобы не вызывать платформенный канал.
///
/// Возвращает `true`, если файл отправлен или сохранён, и `false`, если
/// пользователь закрыл окно без действия.
typedef ShareFile = Future<bool> Function(String path);

/// Открывает системное «Поделиться» для CSV-файла по пути [path].
///
/// Возвращает `true`, если файл отправлен или сохранён, и `false` при отмене:
/// отмена не ошибка и сообщения не требует. Ответ `null` (старая нативная
/// сборка, которая не сообщала результат) считаем успехом. Ошибка на стороне
/// Android или iOS приходит как исключение [PlatformException].
Future<bool> shareCsvFile(String path) async {
  final done = await shareChannel.invokeMethod<bool>(shareCsvFileMethod, {
    shareCsvFilePathArg: path,
  });
  return done ?? true;
}
