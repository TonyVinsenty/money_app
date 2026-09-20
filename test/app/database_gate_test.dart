import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/app/database_gate.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/database/open_app_database.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

import '../support/in_memory_database.dart';

/// База, которая запоминает, что её закрыли.
class _SpyDatabase extends AppDatabase {
  // «Главная» теперь подписана на поток из базы; без closeStreamsSynchronously
  // отписка оставляет «висящий» таймер (как в support/in_memory_database.dart).
  _SpyDatabase()
    : super(
        DatabaseConnection(
          NativeDatabase.memory(),
          closeStreamsSynchronously: true,
        ),
      );

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
    expect(find.text(databaseErrorDataWarning), findsOneWidget);
    expect(databaseErrorTitle, 'Не удалось открыть базу данных');
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

  testWidgets('«Подробности (для разработчика)» свёрнуты, после тапа виден '
      'текст ошибки', (tester) async {
    await _pumpApp(tester, _alwaysFails);
    await tester.pump();

    expect(databaseDetailsLabel, 'Подробности (для разработчика)');
    expect(find.text(databaseDetailsLabel), findsOneWidget);
    expect(find.textContaining('boom-technical-details'), findsNothing);
    expect(find.text(databaseCopyDetailsLabel), findsNothing);
    // Человеческий текст не содержит имён исключений.
    expect(find.textContaining('StateError'), findsNothing);

    await tester.tap(find.text(databaseDetailsLabel));
    await tester.pumpAndSettle();

    expect(find.textContaining('boom-technical-details'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text(databaseCopyDetailsLabel), findsOneWidget);
  });

  testWidgets('у заголовка ошибки есть признаки header и liveRegion', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pumpApp(tester, _alwaysFails);
    await tester.pump();

    expect(
      tester.getSemantics(find.text(databaseErrorTitle)),
      isSemantics(
        label: databaseErrorTitle,
        isHeader: true,
        isLiveRegion: true,
      ),
    );
    handle.dispose();
  });

  group('повторная попытка', () {
    testWidgets('успешная попытка открывает приложение', (tester) async {
      var calls = 0;
      final second = Completer<AppDatabase>();
      await _pumpApp(tester, () {
        calls++;
        return calls == 1 ? _alwaysFails() : second.future;
      });
      await tester.pump();
      _expectErrorScreen();
      expect(calls, 1);
      // После первой неудачи строки про попытки ещё нет.
      expect(find.textContaining('Не получилось'), findsNothing);

      await tester.tap(find.text(databaseRetryLabel));
      await tester.pump();
      expect(calls, 2);

      second.complete(await openInMemoryDatabase());
      await tester.pump();

      _expectTabs();
      expect(calls, 2);
    });

    testWidgets('во время попытки экран ошибки остаётся, кнопка отключена '
        'и показывает индикатор', (tester) async {
      var calls = 0;
      final second = Completer<AppDatabase>();
      await _pumpApp(tester, () {
        calls++;
        return calls == 1 ? _alwaysFails() : second.future;
      });
      await tester.pump();

      await tester.tap(find.text(databaseRetryLabel));
      await tester.pump();

      expect(calls, 2);
      expect(find.text(databaseErrorTitle), findsOneWidget);
      expect(find.text(databaseErrorMessage), findsOneWidget);
      final button = find.byType(FilledButton);
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      expect(
        find.descendant(
          of: button,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(find.text(databaseRetryLabel), findsOneWidget);

      // Тап по отключённой кнопке новой попытки не начинает.
      await tester.tap(button, warnIfMissed: false);
      await tester.pump();
      expect(calls, 2);

      second.completeError(StateError('boom-2'));
      await tester.pump();
    });

    testWidgets('после неудач видны номер попытки и совет, индикатор уходит', (
      tester,
    ) async {
      var calls = 0;
      final attempts = <Completer<AppDatabase>>[];
      await _pumpApp(tester, () {
        calls++;
        if (calls == 1) return _alwaysFails();
        final completer = Completer<AppDatabase>();
        attempts.add(completer);
        return completer.future;
      });
      await tester.pump();

      // Вторая попытка неудачна.
      await tester.tap(find.text(databaseRetryLabel));
      await tester.pump();
      attempts[0].completeError(StateError('boom-2'));
      await tester.pump();

      _expectErrorScreen();
      expect(find.text('Не получилось. Попытка 2.'), findsOneWidget);
      expect(find.text(databaseRetryUnlikelyMessage), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull,
      );

      // Третья попытка неудачна.
      await tester.tap(find.text(databaseRetryLabel));
      await tester.pump();
      // Пока идёт попытка, старая строка не висит.
      expect(find.textContaining('Не получилось'), findsNothing);
      attempts[1].completeError(StateError('boom-3'));
      await tester.pump();

      _expectErrorScreen();
      expect(find.text('Не получилось. Попытка 3.'), findsOneWidget);
      expect(find.text('Не получилось. Попытка 2.'), findsNothing);
      expect(find.text(databaseRetryUnlikelyMessage), findsOneWidget);
      expect(calls, 3);
    });

    testWidgets('строка о неудаче озвучивается (liveRegion)', (tester) async {
      final handle = tester.ensureSemantics();
      var calls = 0;
      await _pumpApp(tester, () {
        calls++;
        return _alwaysFails();
      });
      await tester.pump();
      await tester.tap(find.text(databaseRetryLabel));
      await tester.pump();
      await tester.pump();

      expect(
        tester.getSemantics(find.text('Не получилось. Попытка 2.')),
        isSemantics(isLiveRegion: true),
      );
      expect(calls, 2);
      handle.dispose();
    });
  });

  group('копирование подробностей', () {
    late List<String?> clipboard;

    setUp(() {
      clipboard = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') {
              final arguments = call.arguments as Map<Object?, Object?>;
              clipboard.add(arguments['text'] as String?);
            }
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets(
      'кнопка кладёт текст ошибки в буфер и показывает «Скопировано»',
      (tester) async {
        await _pumpApp(tester, _alwaysFails);
        await tester.pump();
        await tester.tap(find.text(databaseDetailsLabel));
        await tester.pumpAndSettle();
        expect(find.text(databaseCopiedMessage), findsNothing);

        await tester.ensureVisible(find.text(databaseCopyDetailsLabel));
        await tester.tap(find.text(databaseCopyDetailsLabel));
        await tester.pump();
        await tester.pump();

        expect(clipboard, hasLength(1));
        expect(clipboard.single, contains('boom-technical-details'));
        expect(find.text(databaseCopiedMessage), findsOneWidget);
      },
    );
  });

  group('индикатор загрузки', () {
    testWidgets('до задержки индикатора нет, после — есть', (tester) async {
      final completer = Completer<AppDatabase>();
      await _pumpApp(tester, () => completer.future);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);

      await tester.pump(const Duration(milliseconds: 250));
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

      completer.complete(await openInMemoryDatabase());
      await tester.pump();
      _expectTabs();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('быстрое открытие не показывает индикатор ни разу', (
      tester,
    ) async {
      await _pumpApp(tester, openInMemoryDatabase);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pump();
      _expectTabs();

      // Таймер отменён: спустя секунду индикатор не появляется.
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      _expectTabs();
    });

    testWidgets('быстрая ошибка тоже без индикатора', (tester) async {
      await _pumpApp(tester, _alwaysFails);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      _expectErrorScreen();
    });
  });

  testWidgets('при удачном открытии экран ошибки не появляется ни разу', (
    tester,
  ) async {
    final completer = Completer<AppDatabase>();
    await _pumpApp(tester, () => completer.future);

    // Кадр загрузки после задержки: индикатор с подписью, ни ошибки, ни
    // вкладок.
    await tester.pump(databaseSpinnerDelay);
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
