import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

void main() {
  testWidgets('MoneyApp показывает заголовок и заглушку', (tester) async {
    final settings = AppSettingsController();
    addTearDown(settings.dispose);

    await tester.pumpWidget(MoneyApp(settings: settings));

    expect(find.text('Money App'), findsOneWidget);
    expect(find.text('Здесь скоро появятся ваши расходы'), findsOneWidget);
  });

  testWidgets('смена themeMode у контроллера меняет яркость темы', (
    tester,
  ) async {
    final settings = AppSettingsController();
    addTearDown(settings.dispose);
    await tester.pumpWidget(MoneyApp(settings: settings));

    Brightness currentBrightness() =>
        Theme.of(tester.element(find.byType(Scaffold))).brightness;

    settings.setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    expect(currentBrightness(), Brightness.dark);

    settings.setThemeMode(ThemeMode.light);
    await tester.pumpAndSettle();
    expect(currentBrightness(), Brightness.light);
  });
}
