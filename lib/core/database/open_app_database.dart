import 'dart:io';

import 'package:drift/native.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:path_provider/path_provider.dart';

/// Имя файла базы данных приложения.
const appDatabaseFileName = 'zuno.sqlite';

/// Открывает базу приложения в файле [appDatabaseFileName] внутри
/// [directory]. Если файла ещё нет — создаёт его вместе со схемой.
///
/// Каталог [directory] должен уже существовать: этот код сам каталоги не
/// создаёт. Каталог документов приложения есть всегда (его создаёт система),
/// поэтому отсутствие каталога — ошибка вызывающего кода (например, опечатка
/// в пути), и лучше сказать об этом сразу, чем молча создать лишнюю папку.
///
/// Соединение открывается принудительно: файл и схема создаются здесь, а не
/// при первом запросе где-то на экране. Запросы выполняются в отдельном
/// потоке (isolate), чтобы не тормозить интерфейс.
Future<AppDatabase> openAppDatabaseIn(Directory directory) async {
  if (!directory.existsSync()) {
    throw FileSystemException(
      'Каталог для базы данных не существует',
      directory.path,
    );
  }

  final file = File.fromUri(directory.uri.resolve(appDatabaseFileName));
  final database = AppDatabase(NativeDatabase.createInBackground(file));
  try {
    await database.customSelect('SELECT 1').get();
  } catch (_) {
    await database.close();
    rethrow;
  }
  return database;
}

/// Открывает базу приложения в каталоге документов приложения.
///
/// Путь к этому каталогу знает только операционная система, поэтому его
/// подсказывает плагин `path_provider`. Так как плагин нативный, здесь
/// нужен полностью запущенный Flutter (см. `main()`).
Future<AppDatabase> openAppDatabase() async {
  final directory = await getApplicationDocumentsDirectory();
  return openAppDatabaseIn(directory);
}
