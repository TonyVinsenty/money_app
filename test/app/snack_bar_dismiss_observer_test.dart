import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/snack_bar_dismiss_observer.dart';

final _navigator = GlobalKey<NavigatorState>();

Future<ScaffoldMessengerState> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: _navigator,
      navigatorObservers: [SnackBarDismissObserver()],
      home: const Scaffold(body: Text('Категории')),
    ),
  );
  final messenger = ScaffoldMessenger.of(
    tester.element(find.text('Категории')),
  );
  messenger.showSnackBar(
    SnackBar(
      content: const Text('Категория в архиве'),
      duration: const Duration(seconds: 6),
      action: SnackBarAction(label: 'Отменить', onPressed: () {}),
    ),
  );
  await tester.pumpAndSettle();
  expect(find.text('Отменить'), findsOneWidget);
  return messenger;
}

void main() {
  testWidgets('открыли новый экран: «Вернуть» не переезжает на него', (
    tester,
  ) async {
    await _pump(tester);

    _navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          body: const Text('Правка категории'),
          bottomNavigationBar: FilledButton(
            onPressed: () {},
            child: const Text('В архив'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Отменить'), findsNothing);
    // Кнопку внизу формы ничто не закрывает: касание доходит.
    await tester.tap(find.text('В архив'));
  });

  testWidgets('диалог поверх того же экрана сообщение не трогает', (
    tester,
  ) async {
    await _pump(tester);

    unawaited(
      showDialog<void>(
        context: _navigator.currentContext!,
        builder: (_) => const AlertDialog(content: Text('Точно?')),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Точно?'), findsOneWidget);
    expect(find.text('Отменить'), findsOneWidget);
  });

  testWidgets('без сообщения переход ничего не ломает', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: _navigator,
        navigatorObservers: [SnackBarDismissObserver()],
        home: const Scaffold(body: Text('Категории')),
      ),
    );
    _navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Text('Дальше')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Дальше'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
