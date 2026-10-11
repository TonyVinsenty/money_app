import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/keyboard_dismiss_observer.dart';

class _FieldPage extends StatelessWidget {
  const _FieldPage({this.autofocus = false, this.focusNode});

  final bool autofocus;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: TextField(autofocus: autofocus, focusNode: focusNode),
  );
}

void main() {
  late List<String> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.textInput, (call) async {
          calls.add(call.method);
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.textInput, null);
  });

  testWidgets('при pop фокус снимается и уходит TextInput.hide', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        navigatorObservers: [KeyboardDismissObserver()],
        home: const Scaffold(),
      ),
    );
    unawaited(
      navKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => _FieldPage(autofocus: true, focusNode: node),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(node.hasFocus, isTrue);

    // Свой перехват ставим после показа поля: тестовая клавиатура сама
    // занимает этот канал при работе с текстовым полем.
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.textInput, (call) async {
          calls.add(call.method);
          return null;
        });
    navKey.currentState!.pop();
    await tester.pump();
    await tester.idle();

    expect(node.hasFocus, isFalse);
    expect(calls, contains('TextInput.hide'));
    await tester.pumpAndSettle();
  });

  testWidgets('при push экрана с autofocus фокус остаётся у нового поля', (
    tester,
  ) async {
    final node = FocusNode();
    addTearDown(node.dispose);
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        navigatorObservers: [KeyboardDismissObserver()],
        home: const _FieldPage(),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();

    unawaited(
      navKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => _FieldPage(autofocus: true, focusNode: node),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(node.hasFocus, isTrue);
  });
}
