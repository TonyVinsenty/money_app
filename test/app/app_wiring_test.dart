import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/database_gate.dart';
import 'package:money_app/app/open_and_seed_database.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/id/id_generator.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

import '../support/in_memory_database.dart';

/// Генератор id, у которого можно «сломать» и «починить» причину сбоя:
/// пока [broken], всегда отдаёт один и тот же id (второй вставке не пройти
/// уникальность), после починки выдаёт разные.
final class _RepairableIdGenerator implements IdGenerator {
  bool broken = true;
  int _counter = 0;

  @override
  String newId() {
    if (broken) {
      return 'same-id';
    }
    _counter++;
    return 'id-$_counter';
  }
}

void main() {
  late AppSettingsController settings;

  setUp(() {
    settings = AppSettingsController();
  });

  tearDown(() {
    settings.dispose();
  });

  testWidgets('после открытия под AppShell доступен AppScope', (tester) async {
    await tester.pumpWidget(
      MoneyApp(
        settings: settings,
        openDatabase: () => openAndSeedDatabase(openInMemoryDatabase),
      ),
    );
    await tester.pump();

    final bar = find.byType(NavigationBar);
    expect(bar, findsOneWidget);
    final services = AppScope.maybeOf(tester.element(bar));
    expect(services, isNotNull);
    // Тот же контроллер настроек, что и выше MaterialApp.
    expect(services!.settings, same(settings));
  });

  testWidgets('смена темы не пересоздаёт репозитории в scope', (tester) async {
    await tester.pumpWidget(
      MoneyApp(
        settings: settings,
        openDatabase: () => openAndSeedDatabase(openInMemoryDatabase),
      ),
    );
    await tester.pump();
    final before = AppScope.maybeOf(tester.element(find.byType(NavigationBar)));

    settings.setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();

    final after = AppScope.maybeOf(tester.element(find.byType(NavigationBar)));
    expect(before, isNotNull);
    expect(after, same(before));
  });

  testWidgets('падение засева показывает экран ошибки, «Повторить» чинит', (
    tester,
  ) async {
    final ids = _RepairableIdGenerator();
    await tester.pumpWidget(
      MoneyApp(
        settings: settings,
        openDatabase: () =>
            openAndSeedDatabase(openInMemoryDatabase, idGenerator: ids),
      ),
    );
    await tester.pump();

    expect(find.text(databaseErrorTitle), findsOneWidget);
    expect(find.text(databaseRetryLabel), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);

    ids.broken = false;
    await tester.tap(find.text(databaseRetryLabel));
    await tester.pump();

    expect(find.text(databaseErrorTitle), findsNothing);
    final bar = find.byType(NavigationBar);
    expect(bar, findsOneWidget);
    expect(AppScope.maybeOf(tester.element(bar)), isNotNull);
  });

  testWidgets('открытая и засеянная база отдаёт 14 категорий через scope', (
    tester,
  ) async {
    late AppDatabase opened;
    await tester.pumpWidget(
      MoneyApp(
        settings: settings,
        openDatabase: () async {
          opened = await openAndSeedDatabase(openInMemoryDatabase);
          return opened;
        },
      ),
    );
    await tester.pump();

    expect(await opened.select(opened.categories).get(), hasLength(14));
  });
}
