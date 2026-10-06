import 'package:flutter/services.dart';

/// Канал к нативному коду Android и iOS (см. `MainActivity.kt` и
/// `AppDelegate.swift`).
///
/// Через него файл уходит в системное «Поделиться» без пакета `share_plus`:
/// окно открывается из приложения и не ждёт ответа, поэтому выбранное
/// приложение (например, Telegram) не остаётся внутри окна Zuno.
const shareChannel = MethodChannel('com.tonyvinsenty.zuno/share');

/// Имя метода канала; в `MainActivity.kt` и `AppDelegate.swift` такое же.
const shareCsvFileMethod = 'shareCsvFile';

/// Ключ аргумента с путём к файлу; нативный код читает его под этим же именем.
const shareCsvFilePathArg = 'path';

/// Отправка готового файла наружу по пути [path].
///
/// В приложении это системное «Поделиться» ([shareCsvFile]); в тестах
/// подменяется фейком, чтобы не вызывать платформенный канал.
typedef ShareFile = Future<void> Function(String path);

/// Открывает системное «Поделиться» для CSV-файла по пути [path].
///
/// Результат шаринга (в том числе отмену пользователем) не разбираем: отмена
/// не ошибка и сообщения не требует. Ошибка на стороне Android или iOS приходит
/// как исключение [PlatformException].
Future<void> shareCsvFile(String path) async {
  await shareChannel.invokeMethod<void>(shareCsvFileMethod, {
    shareCsvFilePathArg: path,
  });
}
