import 'package:flutter/services.dart';

/// Канал к нативному коду Android (см. `MainActivity.kt`).
///
/// Через него файл уходит в системное «Поделиться» без пакета `share_plus`:
/// окно открывается из приложения и не ждёт ответа, поэтому выбранное
/// приложение (например, Telegram) не остаётся внутри окна Zuno.
const shareChannel = MethodChannel('com.tonyvinsenty.zuno/share');

/// Отправка готового файла наружу по пути [path].
///
/// В приложении это системное «Поделиться» ([shareCsvFile]); в тестах
/// подменяется фейком, чтобы не вызывать платформенный канал.
typedef ShareFile = Future<void> Function(String path);

/// Открывает системное «Поделиться» для CSV-файла по пути [path].
///
/// Результат шаринга (в том числе отмену пользователем) не разбираем: отмена
/// не ошибка и сообщения не требует. Ошибка на стороне Android приходит
/// как исключение [PlatformException].
Future<void> shareCsvFile(String path) async {
  await shareChannel.invokeMethod<void>('shareCsvFile', {'path': path});
}
