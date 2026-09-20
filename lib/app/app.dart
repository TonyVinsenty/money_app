import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/app_shell.dart';
import 'package:money_app/app/app_tabs.dart';
import 'package:money_app/app/database_gate.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

/// Корневой виджет приложения: тема, язык и каркас с нижней навигацией.
class MoneyApp extends StatelessWidget {
  const MoneyApp({
    required this.settings,
    required this.openDatabase,
    this.startOverDatabase,
    super.key,
  });

  /// Настройки нужны выше `MaterialApp` (тема), а тема должна работать уже
  /// до открытия базы: на экране загрузки и на экране ошибки. Поэтому
  /// контроллер создаётся снаружи и живёт выше `AppScope`; тот же экземпляр
  /// потом передаётся и в `AppScope`, чтобы экраны видели те же настройки.
  final AppSettingsController settings;

  /// Открывает базу данных. Вызывается внутри приложения (см. [DatabaseGate]),
  /// а не до `runApp`, чтобы сбой открытия показывался экраном, а не
  /// закрывал приложение.
  final Future<AppDatabase> Function() openDatabase;

  /// Убирает файл базы в сторону для режима «Начать заново» на экране ошибки
  /// (см. [DatabaseGate.onStartOver]). Null — кнопки нет.
  final Future<void> Function()? startOverDatabase;

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
          onGenerateRoute: onGenerateAppRoute,
          home: DatabaseGate(
            open: openDatabase,
            onStartOver: startOverDatabase,
            // AppScope появляется только когда база открыта: до этого
            // показан индикатор или экран ошибки, а зависимостям без базы
            // взяться неоткуда. Тот же экземпляр settings попадает и в scope.
            builder: (context, database) => AppScopeHost(
              database: database,
              settings: settings,
              child: AppShell(tabs: defaultAppTabs),
            ),
          ),
        );
      },
    );
  }
}
