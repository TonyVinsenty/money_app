import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:money_app/app/app_shell.dart';
import 'package:money_app/app/app_tabs.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

/// Корневой виджет приложения: тема, язык и каркас с нижней навигацией.
class MoneyApp extends StatelessWidget {
  const MoneyApp({required this.settings, this.database, super.key});

  final AppSettingsController settings;

  /// Открытая база данных. Пока её никто не читает: `main()` лишь держит
  /// ссылку. Используется с шага 2.15 (AppScope), поэтому необязательная.
  final AppDatabase? database;

  /// Русский — единственный язык приложения.
  static const appLocale = Locale('ru');

  static const supportedLocales = [appLocale];

  /// Переводы стандартных надписей Flutter (кнопки, календарь, подсказки).
  static const localizationsDelegates = <LocalizationsDelegate<dynamic>>[
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  @override
  Widget build(BuildContext context) {
    // ListenableBuilder перестраивает MaterialApp, когда настройки меняются.
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        return MaterialApp(
          title: 'Zuno',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: settings.themeMode,
          locale: appLocale,
          supportedLocales: supportedLocales,
          localizationsDelegates: localizationsDelegates,
          home: AppShell(tabs: defaultAppTabs),
        );
      },
    );
  }
}
