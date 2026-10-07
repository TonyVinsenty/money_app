import 'package:flutter/services.dart';

/// Канал к нативному коду Android и iOS (см. `MainActivity.kt` и
/// `AppDelegate.swift`): своё окно выбора файла без пакета `file_picker`.
const filesChannel = MethodChannel('com.tonyvinsenty.zuno/files');

/// Имя метода канала; в `MainActivity.kt` и `AppDelegate.swift` такое же.
const pickCsvFileMethod = 'pickCsvFile';

/// Коды ошибок платформы; нативный код отдаёт их под этими же именами.
const pickErrorBusy = 'busy';
const pickErrorNoPicker = 'no_picker';
const pickErrorCopyFailed = 'copy_failed';

/// Выбор файла: путь к копии во временном каталоге приложения или `null`,
/// если пользователь нажал «Отмена». В тестах подменяется фейком.
typedef PickFile = Future<String?> Function();

/// Ошибка выбора файла. [code] — код платформы (см. `pickError*`); тексты для
/// пользователя подбирает экран, здесь их нет.
class PickFileException implements Exception {
  const PickFileException(this.code, [this.details]);

  final String code;
  final String? details;

  @override
  String toString() => 'PickFileException($code, $details)';
}

/// Открывает системное окно выбора файла и возвращает путь к копии файла
/// либо `null` при отмене. Ошибку платформы превращает в [PickFileException].
Future<String?> pickCsvFile() async {
  try {
    return await filesChannel.invokeMethod<String>(pickCsvFileMethod);
  } on PlatformException catch (e) {
    throw PickFileException(e.code, e.message);
  }
}
