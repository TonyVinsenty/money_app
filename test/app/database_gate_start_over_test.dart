import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/app/database_gate.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

import '../support/in_memory_database.dart';

Future<AppDatabase> _alwaysFails() =>
    Future<AppDatabase>.error(StateError('boom-technical-details'));

Future<void> _pumpApp(
  WidgetTester tester,
  Future<AppDatabase> Function() open, {
  Future<void> Function()? startOver,
}) async {
  final controller = AppSettingsController();
  addTearDown(controller.dispose);
  await tester.pumpWidget(
    MoneyApp(
      settings: controller,
      openDatabase: open,
      startOverDatabase: startOver,
    ),
  );
  await tester.pump();
}

/// Кнопка «Начать заново» на экране ошибки (не в диалоге).
Finder get _startOverButton => find.widgetWithText(
  TextButton,
  databaseStartOverLabel,
  skipOffstage: false,
);

Finder _dialogButton(String label) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.widgetWithText(TextButton, label),
);

Future<void> _tapStartOver(WidgetTester tester) async {
  await tester.ensureVisible(_startOverButton);
  await tester.tap(_startOverButton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('без onStartOver кнопки «Начать заново» нет', (tester) async {
    await _pumpApp(tester, _alwaysFails);

    expect(find.text(databaseStartOverLabel), findsNothing);
    expect(find.text(databaseErrorTitle), findsOneWidget);
  });

  testWidgets('с onStartOver кнопка есть, заголовок экрана прежний', (
    tester,
  ) async {
    await _pumpApp(tester, _alwaysFails, startOver: () async {});

    expect(databaseErrorTitle, 'Не удалось открыть базу данных');
    expect(find.text(databaseErrorTitle), findsOneWidget);
    expect(_startOverButton, findsOneWidget);
    // Второстепенный путь: не FilledButton, «Повторить» остаётся главной.
    expect(find.byType(FilledButton), findsOneWidget);
    expect(find.text(databaseRetryLabel), findsOneWidget);
  });

  testWidgets('«Отмена» на первом диалоге ничего не запускает', (tester) async {
    var opens = 0;
    var startOvers = 0;
    await _pumpApp(tester, () {
      opens++;
      return _alwaysFails();
    }, startOver: () async => startOvers++);

    await _tapStartOver(tester);
    expect(find.text(databaseStartOverTitle1), findsOneWidget);
    expect(find.text(databaseStartOverBody1), findsOneWidget);

    // Тап мимо диалога его не закрывает.
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(find.text(databaseStartOverTitle1), findsOneWidget);

    await tester.tap(_dialogButton(databaseDialogCancelLabel));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(startOvers, 0);
    expect(opens, 1);
    expect(find.text(databaseErrorTitle), findsOneWidget);
  });

  testWidgets('«Отмена» на втором диалоге ничего не запускает', (tester) async {
    var opens = 0;
    var startOvers = 0;
    await _pumpApp(tester, () {
      opens++;
      return _alwaysFails();
    }, startOver: () async => startOvers++);

    await _tapStartOver(tester);
    await tester.tap(_dialogButton(databaseDialogContinueLabel));
    await tester.pumpAndSettle();

    expect(find.text(databaseStartOverTitle2), findsOneWidget);
    expect(find.text(databaseStartOverBody2), findsOneWidget);
    expect(
      databaseStartOverBody2,
      'Все записи будут потеряны, восстановить можно только из CSV.',
    );

    await tester.tap(_dialogButton(databaseDialogCancelLabel));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(startOvers, 0);
    expect(opens, 1);
  });

  testWidgets('два подтверждения: onStartOver один раз, затем open и '
      'приложение открывается', (tester) async {
    var opens = 0;
    var startOvers = 0;
    await _pumpApp(tester, () {
      opens++;
      return opens == 1 ? _alwaysFails() : openInMemoryDatabase();
    }, startOver: () async => startOvers++);

    await _tapStartOver(tester);
    await tester.tap(_dialogButton(databaseDialogContinueLabel));
    await tester.pumpAndSettle();
    expect(startOvers, 0);
    await tester.tap(_dialogButton(databaseStartOverLabel));
    await tester.pumpAndSettle();

    expect(startOvers, 1);
    expect(opens, 2);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text(databaseErrorTitle), findsNothing);
  });

  testWidgets('пока onStartOver не завершён, обе кнопки отключены', (
    tester,
  ) async {
    final pending = Completer<void>();
    var opens = 0;
    await _pumpApp(tester, () {
      opens++;
      return opens == 1 ? _alwaysFails() : openInMemoryDatabase();
    }, startOver: () => pending.future);

    await _tapStartOver(tester);
    await tester.tap(_dialogButton(databaseDialogContinueLabel));
    await tester.pumpAndSettle();
    await tester.tap(_dialogButton(databaseStartOverLabel));
    // Дожидаемся закрытия диалога (индикатор крутится, pumpAndSettle не
    // подходит).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    expect(tester.widget<TextButton>(_startOverButton).onPressed, isNull);
    expect(
      find.descendant(
        of: find.byType(FilledButton),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(opens, 1);

    pending.complete();
    await tester.pumpAndSettle();
    expect(opens, 2);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('ошибка onStartOver: сообщение, подробности, «Повторить» '
      'работает', (tester) async {
    var opens = 0;
    await _pumpApp(tester, () {
      opens++;
      return opens == 1 ? _alwaysFails() : openInMemoryDatabase();
    }, startOver: () async => throw StateError('boom-start-over'));

    await _tapStartOver(tester);
    await tester.tap(_dialogButton(databaseDialogContinueLabel));
    await tester.pumpAndSettle();
    await tester.tap(_dialogButton(databaseStartOverLabel));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(databaseErrorTitle), findsOneWidget);
    expect(find.text(databaseStartOverFailedMessage), findsOneWidget);
    expect(opens, 1);
    // Кнопки снова доступны.
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    expect(tester.widget<TextButton>(_startOverButton).onPressed, isNotNull);

    await tester.tap(find.text(databaseDetailsLabel));
    await tester.pumpAndSettle();
    expect(find.textContaining('boom-technical-details'), findsOneWidget);
    expect(
      find.textContaining(
        '$databaseStartOverDetailsPrefix'
        'Bad state: boom-start-over',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text(databaseRetryLabel));
    await tester.pumpAndSettle();

    expect(opens, 2);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('сообщение об ошибке сбрасывается при следующей попытке', (
    tester,
  ) async {
    final second = Completer<AppDatabase>();
    var opens = 0;
    await _pumpApp(tester, () {
      opens++;
      return opens == 1 ? _alwaysFails() : second.future;
    }, startOver: () async => throw StateError('boom-start-over'));

    await _tapStartOver(tester);
    await tester.tap(_dialogButton(databaseDialogContinueLabel));
    await tester.pumpAndSettle();
    await tester.tap(_dialogButton(databaseStartOverLabel));
    await tester.pumpAndSettle();
    expect(find.text(databaseStartOverFailedMessage), findsOneWidget);

    await tester.tap(find.text(databaseRetryLabel));
    await tester.pump();
    expect(find.text(databaseStartOverFailedMessage), findsNothing);

    second.completeError(StateError('boom-2'));
    await tester.pumpAndSettle();
    expect(find.text(databaseStartOverFailedMessage), findsNothing);
  });

  testWidgets('строка об ошибке озвучивается (liveRegion)', (tester) async {
    final handle = tester.ensureSemantics();
    await _pumpApp(
      tester,
      _alwaysFails,
      startOver: () async => throw StateError('boom-start-over'),
    );

    await _tapStartOver(tester);
    await tester.tap(_dialogButton(databaseDialogContinueLabel));
    await tester.pumpAndSettle();
    await tester.tap(_dialogButton(databaseStartOverLabel));
    await tester.pumpAndSettle();

    expect(
      tester.getSemantics(find.text(databaseStartOverFailedMessage)),
      isSemantics(isLiveRegion: true),
    );
    handle.dispose();
  });

  testWidgets('на масштабе шрифта 200% нет переполнения', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2.0;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.binding.setSurfaceSize(const Size(360, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpApp(
      tester,
      _alwaysFails,
      startOver: () async => throw StateError('boom-start-over'),
    );
    expect(tester.takeException(), isNull);

    await _tapStartOver(tester);
    expect(tester.takeException(), isNull);
    await tester.tap(_dialogButton(databaseDialogContinueLabel));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(_dialogButton(databaseStartOverLabel));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(databaseStartOverFailedMessage), findsOneWidget);
  });
}
