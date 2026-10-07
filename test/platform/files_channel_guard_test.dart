// Сторож канала выбора файла (шаги i.13–i.14, ADR 0009): имя канала, метода и
// коды ошибок в Dart, Kotlin и Swift совпадают. Нативный код на Windows не
// собирается, поэтому проверяем текстом, как в share_channel_guard_test.dart.

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

/// Проверки только для Swift: канал создаётся в
/// `didInitializeImplicitFlutterEngine`, окно копирует файл само (`asCopy`),
/// закрывается только кнопкой (иначе ответ в Dart мог бы не прийти).
List<String> checkFilesSwift(String source) {
  final errors = checkFilesCommon(source);
  final start = source.indexOf('func didInitializeImplicitFlutterEngine');
  var end = start < 0 ? -1 : source.indexOf('func ', start + 5);
  if (start >= 0 && end < 0) end = source.length;
  final body = start < 0 ? '' : source.substring(start, end);
  if (!body.contains('name: filesChannelName')) {
    errors.add('Канал не создаётся в didInitializeImplicitFlutterEngine');
  }
  for (final needle in [
    'asCopy: true',
    '.commaSeparatedText',
    'UIDocumentPickerDelegate',
    'documentPickerWasCancelled',
    'isModalInPresentation = true',
  ]) {
    if (!source.contains(needle)) errors.add('Не найдено $needle');
  }
  return errors;
}

void main() {
  final swift = File('ios/Runner/AppDelegate.swift').readAsStringSync();
  final kotlin = File(
    'android/app/src/main/kotlin/com/tonyvinsenty/zuno/MainActivity.kt',
  ).readAsStringSync();

  test('MainActivity.kt: канал выбора файла, метод и коды ошибок', () {
    expect(checkFilesCommon(kotlin), isEmpty);
  });

  test('AppDelegate.swift: канал, метод, коды ошибок и окно выбора', () {
    expect(checkFilesSwift(swift), isEmpty);
  });

  test('сторож замечает другое имя канала', () {
    expect(
      checkFilesCommon(kotlin.replaceAll('zuno/files', 'zuno/other')),
      isNotEmpty,
    );
    expect(
      checkFilesSwift(swift.replaceAll('zuno/files', 'zuno/other')),
      isNotEmpty,
    );
  });

  test('сторож замечает канал вне didInitializeImplicitFlutterEngine', () {
    final bad = swift.replaceFirst(
      'name: filesChannelName',
      'name: shareChannelName',
    );
    expect(checkFilesSwift(bad), isNotEmpty);
  });

  test('сторож замечает окно без asCopy', () {
    final bad = swift.replaceAll('asCopy: true', 'asCopy: false');
    expect(checkFilesSwift(bad), isNotEmpty);
  });
}
