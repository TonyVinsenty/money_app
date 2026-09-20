import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/core/database/open_app_database.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

Future<void> main() async {
  // Нужно, чтобы вызывать платформенный код до runApp.
  WidgetsFlutterBinding.ensureInitialized();
  // Загружаем русские названия месяцев и дней для форматирования дат.
  await initializeDateFormatting('ru');

  // Открываем файловую базу: при первом запуске файл создаётся, дальше
  // открывается тот же. Живёт всё время работы приложения, close не нужен.
  final database = await openAppDatabase();

  // Тоже живёт всё время работы приложения, поэтому dispose не нужен.
  final settings = AppSettingsController();
  runApp(MoneyApp(settings: settings, database: database));
}
