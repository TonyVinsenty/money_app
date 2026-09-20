import 'dart:io';

import 'package:money_app/core/database/open_app_database.dart';
import 'package:path_provider/path_provider.dart';

/// Расширение файла базы (то, что идёт после имени).
const _databaseExtension = '.sqlite';

/// Дополнения к имени файла базы, которые SQLite создаёт рядом с ним:
/// журнал записи (`-wal`), общая память (`-shm`) и откатный журнал
/// (`-journal`). Их нужно переносить вместе с основным файлом: оставшийся
/// старый журнал рядом с новой пустой базой был бы к ней применён.
const _companionSuffixes = ['-wal', '-shm', '-journal'];

/// Переименовывает файл базы [appDatabaseFileName] в каталоге [directory] в
/// `zuno_broken_<yyyy-MM-dd_HHmmss>.sqlite` (время берётся из [now]) и
/// возвращает переименованный файл. Если основного файла нет — ничего не
/// делает и возвращает null.
///
/// Файл никогда не удаляется и не перезаписывается: если целевое имя (или имя
/// любого из спутников) занято, к имени добавляется `_2`, `_3` и так далее.
/// Вместе с основным файлом переносятся спутники `-wal`, `-shm`, `-journal`,
/// если они есть.
///
/// Если любое переименование не удалось, уже сделанные откатываются (насколько
/// получится), а исходная ошибка пробрасывается дальше.
///
/// [rename] нужен тестам, чтобы имитировать сбой; по умолчанию файл
/// переименовывается обычным `file.rename(newPath)`.
Future<File?> archiveDatabaseFileIn(
  Directory directory, {
  required DateTime now,
  Future<void> Function(File file, String newPath)? rename,
}) async {
  final doRename =
      rename ?? (File file, String newPath) => file.rename(newPath);

  final main = File.fromUri(directory.uri.resolve(appDatabaseFileName));
  if (!main.existsSync()) {
    return null;
  }

  final baseStem = 'zuno_broken_${_formatTimestamp(now)}';
  String newMainPath(int copy) => directory.uri
      .resolve('$baseStem${copy == 1 ? '' : '_$copy'}$_databaseExtension')
      .toFilePath();

  var copy = 1;
  while (_isTaken(newMainPath(copy))) {
    copy++;
  }
  final targetMain = newMainPath(copy);

  // Пары «откуда → куда»: основной файл первым, затем существующие спутники.
  final moves = <(File, String)>[(main, targetMain)];
  for (final suffix in _companionSuffixes) {
    final companion = File('${main.path}$suffix');
    if (companion.existsSync()) {
      moves.add((companion, '$targetMain$suffix'));
    }
  }

  final done = <(String from, String to)>[];
  try {
    for (final (file, newPath) in moves) {
      await doRename(file, newPath);
      done.add((file.path, newPath));
    }
  } catch (_) {
    // Откат в обратном порядке. Ошибки отката глотаем: исходная ошибка важнее.
    for (final (from, to) in done.reversed) {
      try {
        await File(to).rename(from);
      } catch (_) {}
    }
    rethrow;
  }
  return File(targetMain);
}

/// Занято ли имя [mainPath] или любое имя спутника от него.
bool _isTaken(String mainPath) {
  if (FileSystemEntity.typeSync(mainPath, followLinks: false) !=
      FileSystemEntityType.notFound) {
    return true;
  }
  for (final suffix in _companionSuffixes) {
    if (FileSystemEntity.typeSync('$mainPath$suffix', followLinks: false) !=
        FileSystemEntityType.notFound) {
      return true;
    }
  }
  return false;
}

String _formatTimestamp(DateTime now) {
  String two(int value) => value.toString().padLeft(2, '0');
  final year = now.year.toString().padLeft(4, '0');
  return '$year-${two(now.month)}-${two(now.day)}_'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}';
}

/// Убирает файл базы приложения «в сторону» (см. [archiveDatabaseFileIn]) в
/// каталоге поддержки приложения. Нужен режиму «Начать заново» на экране
/// ошибки открытия базы: старые данные остаются на телефоне под другим именем.
///
/// Путь к каталогу знает только операционная система (плагин `path_provider`),
/// поэтому здесь нужен полностью запущенный Flutter, как и в `openAppDatabase`.
Future<File?> archiveAppDatabase({DateTime? now}) async {
  final directory = await getApplicationSupportDirectory();
  return archiveDatabaseFileIn(directory, now: now ?? DateTime.now());
}
