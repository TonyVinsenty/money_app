import 'package:flutter/material.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

void main() {
  // Живёт всё время работы приложения, поэтому dispose не нужен.
  final settings = AppSettingsController();
  runApp(MoneyApp(settings: settings));
}
