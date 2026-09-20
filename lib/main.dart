import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

Future<void> main() async {
  // Нужно, чтобы вызывать платформенный код до runApp.
  WidgetsFlutterBinding.ensureInitialized();
  // Загружаем русские названия месяцев и дней для форматирования дат.
  await initializeDateFormatting('ru');

  // Живёт всё время работы приложения, поэтому dispose не нужен.
  final settings = AppSettingsController();
  runApp(MoneyApp(settings: settings));
}
