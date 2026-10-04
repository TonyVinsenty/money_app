import 'package:share_plus/share_plus.dart';

/// MIME-тип CSV: подсказка системе, какими приложениями можно открыть файл.
const csvMimeType = 'text/csv';

/// Отправка готового файла наружу по пути [path].
///
/// В приложении это системное «Поделиться» ([shareCsvFile]); в тестах
/// подменяется фейком, чтобы не вызывать платформенный канал.
typedef ShareFile = Future<void> Function(String path);

/// Открывает системное «Поделиться» для CSV-файла по пути [path].
///
/// Результат шаринга (в том числе отмену пользователем) не разбираем: отмена
/// не ошибка и сообщения не требует.
Future<void> shareCsvFile(String path) async {
  await SharePlus.instance.share(
    ShareParams(files: [XFile(path, mimeType: csvMimeType)]),
  );
}
