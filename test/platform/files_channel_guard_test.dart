// Сторож канала выбора файла (шаг i.13, ADR 0009): имя канала, метода и коды
// ошибок в Dart и Kotlin совпадают. iOS добавится в шаге i.14.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/csv_import/presentation/pick_csv_file.dart';

List<String> checkFilesCommon(String source) {
  final errors = <String>[];
  for (final needle in [
    '"${filesChannel.name}"',
    '"$pickCsvFileMethod"',
    '"$pickErrorBusy"',
    '"$pickErrorNoPicker"',
    '"$pickErrorCopyFailed"',
  ]) {
    if (!source.contains(needle)) errors.add('Не найдено $needle');
  }
  return errors;
}

void main() {
  final kotlin = File(
    'android/app/src/main/kotlin/com/tonyvinsenty/zuno/MainActivity.kt',
  ).readAsStringSync();

  test('MainActivity.kt: канал выбора файла, метод и коды ошибок', () {
    expect(checkFilesCommon(kotlin), isEmpty);
  });

  test('сторож замечает другое имя канала', () {
    final bad = kotlin.replaceAll('zuno/files', 'zuno/other');
    expect(checkFilesCommon(bad), isNotEmpty);
  });
}
