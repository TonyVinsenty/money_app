import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/app/open_and_seed_database.dart';
import 'package:money_app/core/database/open_app_database.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

Future<void> main() async {
  // Нужно, чтобы вызывать платформенный код до runApp.
  WidgetsFlutterBinding.ensureInitialized();
  // Загружаем русские названия месяцев и дней для форматирования дат.
  await initializeDateFormatting('ru');

  // Базу открываем не здесь, а внутри приложения (DatabaseGate): если открыть
  // не получится, runApp всё равно вызван и пользователь увидит экран ошибки.
  // Живёт всё время работы приложения, поэтому dispose не нужен.
  final settings = AppSettingsController();
  runApp(
    MoneyApp(
      settings: settings,
      // Открываем базу и сразу засеваем категории по умолчанию. Если засев
      // упадёт, база закроется, а пользователь увидит экран ошибки.
      openDatabase: () => openAndSeedDatabase(openAppDatabase),
    ),
  );
}
