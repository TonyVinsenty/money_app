import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/tap_to_dismiss_snack_content.dart';
import 'package:money_app/features/transactions/presentation/quick_add/saved_snack_bar.dart';

Future<void> _pump(WidgetTester tester, {VoidCallback? onAction}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const TapToDismissSnackContent(child: Text('Плашка')),
                persist: false,
                action: SnackBarAction(
                  label: 'Отменить',
                  onPressed: onAction ?? () {},
                ),
              ),
            ),
            child: const Text('Показать'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Показать'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('касание текста плашки закрывает её, действие не зовётся', (
    tester,
  ) async {
    var actions = 0;
    await _pump(tester, onAction: () => actions++);
    expect(find.text('Плашка'), findsOneWidget);
    await tester.tap(find.text('Плашка'));
    await tester.pumpAndSettle();
    expect(find.text('Плашка'), findsNothing);
    expect(actions, 0);
  });

  testWidgets('кнопка действия по-прежнему зовёт своё действие', (
    tester,
  ) async {
    var actions = 0;
    await _pump(tester, onAction: () => actions++);
    await tester.tap(find.text('Отменить'));
    await tester.pumpAndSettle();
    expect(actions, 1);
    expect(find.text('Плашка'), findsNothing);
  });

  testWidgets('для скринридера: у плашки есть действие касания', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    final node = tester.getSemantics(find.text('Плашка'));
    final data = node.getSemanticsData();
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(node.hintOverrides?.onTapHint, 'Скрыть');
    expect(data.label, 'Плашка');
    // Отдельного узла «Скрыть» без текста нет: подсказка живёт в узле текста.
    expect(find.bySemanticsLabel('Скрыть'), findsNothing);
    handle.dispose();
  });

  testWidgets('семантическое действие tap закрывает плашку', (tester) async {
    final handle = tester.ensureSemantics();
    var actions = 0;
    await _pump(tester, onAction: () => actions++);
    tester.semantics.performAction(
      find.semantics.byLabel('Плашка'),
      SemanticsAction.tap,
    );
    await tester.pumpAndSettle();
    expect(find.text('Плашка'), findsNothing);
    expect(actions, 0);
    handle.dispose();
  });

  testWidgets('SavedSnackBar: один узел с подписью, касанием и подсказкой', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                SavedSnackBar.build(
                  text: 'Сохранено: расход 350 ₽ · Еда',
                  spokenText: 'Сохранено: расход 350 рублей · Еда',
                  onUndo: () {},
                ),
              ),
              child: const Text('Показать'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Показать'));
    await tester.pumpAndSettle();

    final node = tester.getSemantics(
      find.text('Сохранено: расход 350 ₽ · Еда'),
    );
    final data = node.getSemanticsData();
    expect(data.label, 'Сохранено: расход 350 рублей · Еда');
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    expect(node.hintOverrides?.onTapHint, 'Скрыть');
    expect(find.bySemanticsLabel('Скрыть'), findsNothing);
    handle.dispose();
  });
}
