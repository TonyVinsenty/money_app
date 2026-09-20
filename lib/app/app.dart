import 'package:flutter/material.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

/// Корневой виджет приложения. Пока это заглушка.
class MoneyApp extends StatelessWidget {
  const MoneyApp({required this.settings, super.key});

  final AppSettingsController settings;

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
