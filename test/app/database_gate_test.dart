import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/app/database_gate.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/database/open_app_database.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

import '../support/in_memory_database.dart';

/// База, которая запоминает, что её закрыли.
class _SpyDatabase extends AppDatabase {
  _SpyDatabase() : super(NativeDatabase.memory());

  bool closed = false;

  @override
  Future<void> close() {
    closed = true;
    return super.close();
  }
}

const _tabLabels = ['Главная', 'История', 'Аналитика', 'Баланс', 'Настройки'];

Future<AppDatabase> _alwaysFails() =>
    Future<AppDatabase>.error(StateError('boom-technical-details'));

Future<void> _pumpApp(
  WidgetTester tester,
  Future<AppDatabase> Function() open, {
  AppSettingsController? settings,
}) async {
  final controller = settings ?? AppSettingsController();
  if (settings == null) {
    addTearDown(controller.dispose);
  }
  await tester.pumpWidget(MoneyApp(settings: controller, openDatabase: open));
}

void _expectErrorScreen() {
  expect(find.text(databaseErrorTitle), findsOneWidget);
  expect(find.text(databaseRetryLabel), findsOneWidget);
  expect(find.byType(NavigationBar), findsNothing);
  expect(find.byType(CircularProgressIndicator), findsNothing);
}

void _expectTabs() {
  final bar = find.byType(NavigationBar);
  expect(bar, findsOneWidget);
  for (final label in _tabLabels) {
    expect(
      find.descendant(of: bar, matching: find.text(label)),
      findsOneWidget,
    );
  }
  expect(find.text(databaseErrorTitle), findsNothing);
}

void main() {
  testWidgets('при ошибке открытия виден экран ошибки, а не приложение', (
    tester,
  ) async {
    await _pumpApp(tester, _alwaysFails);
    await tester.pump();

    _expectErrorScreen();
    expect(find.text(databaseErrorMessage), findsOneWidget);
    // Крупная зона нажатия: не ниже 48 логических пикселей.
    expect(tester.getSize(find.byType(FilledButton)).height, greaterThan(47));
  });

  testWidgets('синхронный сбой open() тоже показывает экран ошибки', (
    tester,
  ) async {
    await _pumpApp(tester, () => throw StateError('sync-boom'));
    await tester.pump();

    _expectErrorScreen();
  });

  testWidgets('«Подробности» свёрнуты, после тапа виден текст ошибки', (
    tester,
  ) async {
    await _pumpApp(tester, _alwaysFails);
    await tester.pump();

    expect(find.text(databaseDetailsLabel), findsOneWidget);
    expect(find.textContaining('boom-technical-details'), findsNothing);
    // Человеческий текст не содержит имён исключений.
    expect(find.textContaining('StateError'), findsNothing);

    await tester.tap(find.text(databaseDetailsLabel));
    await tester.pumpAndSettle();

    expect(find.textContaining('boom-technical-details'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('«Повторить» делает новую попытку и открывает приложение', (
    tester,
  ) async {
    var calls = 0;
    final second = Completer<AppDatabase>();
    await _pumpApp(tester, () {
      calls++;
      return calls == 1 ? _alwaysFails() : second.future;
    });
    await tester.pump();
    _expectErrorScreen();
    expect(calls, 1);

    await tester.tap(find.text(databaseRetryLabel));
    await tester.pump();

    // Снова идёт загрузка, ошибки на экране нет.
    expect(calls, 2);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text(databaseErrorTitle), findsNothing);

    second.complete(await openInMemoryDatabase());
    await tester.pump();

    _expectTabs();
    expect(calls, 2);
  });

  testWidgets('повторная неудача снова показывает экран ошибки', (
    tester,
  ) async {
    var calls = 0;
    final second = Completer<AppDatabase>();
    await _pumpApp(tester, () {
      calls++;
      return calls == 1 ? _alwaysFails() : second.future;
    });
    await tester.pump();
    _expectErrorScreen();

    await tester.tap(find.text(databaseRetryLabel));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    second.completeError(StateError('boom-again'));
    await tester.pump();

    _expectErrorScreen();
    expect(calls, 2);
  });

  testWidgets('при удачном открытии экран ошибки не появляется ни разу', (
    tester,
  ) async {
    final completer = Completer<AppDatabase>();
    await _pumpApp(tester, () => completer.future);

    // Кадр загрузки: индикатор с подписью, ни ошибки, ни вкладок.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .semanticsLabel,
      databaseLoadingLabel,
    );
    expect(find.text(databaseErrorTitle), findsNothing);
    expect(find.text(databaseRetryLabel), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);

    // Ждём ещё кадр-другой: загрузка не превращается в ошибку.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(databaseErrorTitle), findsNothing);

    completer.complete(await openInMemoryDatabase());
    await tester.pump();

    _expectTabs();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('open() вызывается один раз при перерисовках', (tester) async {
    var calls = 0;
    final settings = AppSettingsController();
    addTearDown(settings.dispose);
    await _pumpApp(tester, () {
      calls++;
      return openInMemoryDatabase();
    }, settings: settings);
    await tester.pump();
    _expectTabs();

    settings.setThemeMode(ThemeMode.dark);
    await tester.pumpAndSettle();
    settings.setThemeMode(ThemeMode.light);
    await tester.pumpAndSettle();

    _expectTabs();
    expect(calls, 1);
  });

  testWidgets('шлюз закрывает базу, когда удаляется из дерева', (tester) async {
    final database = _SpyDatabase();
    await _pumpApp(tester, () async => database);
    await tester.pump();
    _expectTabs();
    expect(database.closed, isFalse);

    await tester.pumpWidget(const SizedBox());

    expect(database.closed, isTrue);
  });

  testWidgets('попытка, завершившаяся после удаления шлюза, закрывает базу', (
    tester,
  ) async {
    final database = _SpyDatabase();
    final completer = Completer<AppDatabase>();
    await _pumpApp(tester, () => completer.future);

    await tester.pumpWidget(const SizedBox());
    completer.complete(database);
    await tester.pump();

    expect(database.closed, isTrue);
  });

  group('реальное открытие файла', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('zuno_gate_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    testWidgets('файл «не база» доходит до экрана ошибки', (tester) async {
      File.fromUri(tempDir.uri.resolve(appDatabaseFileName))
          .writeAsStringSync('это не база');

      // Реальный ввод-вывод не работает в fake-async, поэтому весь тест
      // идёт через runAsync и реальные паузы.
      await tester.runAsync(() async {
        await _pumpApp(tester, () => openAppDatabaseIn(tempDir));

        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (find.text(databaseErrorTitle).evaluate().isEmpty &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        }

        _expectErrorScreen();

        await tester.tap(find.text(databaseDetailsLabel));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.textContaining('file is not a database'), findsOneWidget);
      });
    });
  });
}
