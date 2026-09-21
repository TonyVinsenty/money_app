import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/features/settings/data/settings_repository_impl.dart';
import 'package:money_app/features/settings/domain/settings_repository.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

/// База, которую шлюз «закрывает» вхолостую: так один и тот же файл
/// (здесь — память) переживает два запуска приложения, как файл на телефоне.
class _SurvivingDatabase extends AppDatabase {
  _SurvivingDatabase()
    : super(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );

  @override
  Future<void> close() async {}

  Future<void> reallyClose() => super.close();
}

ThemeMode _appThemeMode(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;

Future<void> _openSettingsTab(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Настройки'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late _SurvivingDatabase db;

  setUp(() {
    db = _SurvivingDatabase();
  });

  tearDown(() => db.reallyClose());

  /// Один «запуск приложения»: новый контроллер, та же база.
  Future<AppSettingsController> launch(WidgetTester tester) async {
    final settings = AppSettingsController();
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MoneyApp(settings: settings, openDatabase: () async => db),
    );
    await tester.pumpAndSettle();
    return settings;
  }

  Future<void> closeApp(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets('перезапустили: тема та же, что выбрали в «Настройках»', (
    tester,
  ) async {
    final first = await launch(tester);
    expect(_appThemeMode(tester), ThemeMode.system);

    await _openSettingsTab(tester);
    await tester.tap(find.text('Тёмная'));
    await tester.pumpAndSettle();
    expect(first.themeMode, ThemeMode.dark);
    expect(_appThemeMode(tester), ThemeMode.dark);

    // Выбор попал в базу.
    final stored = await tester.runAsync(
      () => DriftSettingsRepository(db).read(themeModeSettingKey),
    );
    expect(stored, 'dark');

    await closeApp(tester);
    final second = await launch(tester);

    expect(second.themeMode, ThemeMode.dark);
    expect(_appThemeMode(tester), ThemeMode.dark);
  });

  testWidgets('чистая база: запуск в теме «как в системе»', (tester) async {
    final settings = await launch(tester);

    expect(settings.themeMode, ThemeMode.system);
    expect(_appThemeMode(tester), ThemeMode.system);
  });

  testWidgets('основной экран строится сразу в сохранённой теме', (
    tester,
  ) async {
    await tester.runAsync(
      () => DriftSettingsRepository(db).write(themeModeSettingKey, 'dark'),
    );

    // Смотрим тему каждого кадра, в котором уже есть вкладки.
    final settings = AppSettingsController();
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MoneyApp(settings: settings, openDatabase: () async => db),
    );
    final modesWithTabs = <ThemeMode>[];
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.byType(NavigationBar).evaluate().isNotEmpty) {
        modesWithTabs.add(_appThemeMode(tester));
      }
    }

    expect(modesWithTabs, isNotEmpty);
    expect(modesWithTabs.toSet(), {ThemeMode.dark});
  });
}
