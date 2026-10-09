import 'dart:convert';
import 'dart:io';

import 'package:money_app/core/time/clock.dart';
import 'package:money_app/features/accounts/domain/accounts_repository.dart';
import 'package:money_app/features/categories/domain/categories_repository.dart';
import 'package:money_app/features/export/domain/transactions_export.dart';
import 'package:money_app/features/transactions/domain/transactions_repository.dart';
import 'package:path_provider/path_provider.dart';

/// Каталог, куда пишется файл экспорта. В приложении — временный каталог
/// (`getTemporaryDirectory`), в тестах подставляется свой.
typedef ExportDirectoryProvider = Future<Directory> Function();

/// Записывает [content] в файл [fileName] внутри каталога и возвращает путь.
///
/// Только запись на диск: отправку наружу делает шаг 6.3 (`share_plus`).
/// Текст кодируется в UTF-8; BOM уже стоит в начале [content] (см. кодек).
Future<String> writeExportFile({
  required String fileName,
  required String content,
  ExportDirectoryProvider directoryProvider = getTemporaryDirectory,
}) async {
  final directory = await directoryProvider();
  final file = File('${directory.path}${Platform.pathSeparator}$fileName');
  await file.writeAsString(content, encoding: utf8, flush: true);
  return file.path;
}

/// Выгрузка всех живых операций в файл CSV во временном каталоге.
///
/// Порядок действий «всё или ничего»: сначала читаем и собираем текст, и
/// только потом пишем файл. Если что-то испорчено, исключение вылетает до
/// записи, и файл не появляется.
class TransactionsExporter {
  // Приватные именованные параметры (Dart 3.12+): снаружи они называются
  // без подчёркивания, как и в остальном проекте.
  TransactionsExporter({
    required this._transactions,
    required this._categories,
    required this._accounts,
    required this._clock,
    this._directoryProvider = getTemporaryDirectory,
  });

  final TransactionsRepository _transactions;
  final CategoriesRepository _categories;
  final AccountsRepository _accounts;
  final Clock _clock;
  final ExportDirectoryProvider _directoryProvider;

  /// Возвращает путь к созданному файлу экспорта.
  ///
  /// Бросает `DataCorruptedException`, если в базе есть испорченная строка
  /// или операция ссылается на отсутствующую категорию; тогда файл не создаётся.
  Future<String> exportToTempFile() async {
    final transactions = await _transactions.findAllLive();
    // watchAll отдаёт текущий список первым событием; берём его и отписываемся.
    final categories = await _categories.watchAll().first;
    final accounts = await _accounts.watchAll().first;
    final content = buildTransactionsCsv(
      transactions: transactions,
      categories: categories,
      accounts: accounts,
    );
    return writeExportFile(
      fileName: exportFileName(_clock),
      content: content,
      directoryProvider: _directoryProvider,
    );
  }
}
