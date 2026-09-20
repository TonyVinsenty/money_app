import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

/// Корневой виджет приложения. Пока это заглушка.
class MoneyApp extends StatelessWidget {
  const MoneyApp({required this.settings, super.key});

  final AppSettingsController settings;

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
          home: Scaffold(
            appBar: AppBar(title: const Text('Zuno')),
            body: const Center(
              child: Text('Здесь скоро появятся ваши расходы'),
            ),
          ),
        );
      },
    );
  }
}
