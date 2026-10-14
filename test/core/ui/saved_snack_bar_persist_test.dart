import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/features/transactions/presentation/quick_add/saved_snack_bar.dart';

Future<void> _show(WidgetTester tester, {required bool persist}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              SavedSnackBar.build(
                text: 'Операция удалена',
                spokenText: 'Операция удалена',
                onUndo: () {},
                persist: persist,
              ),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(SavedSnackBar.duration + const Duration(seconds: 5));
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  testWidgets('по умолчанию сообщение с «Отменить» исчезает само', (
    tester,
  ) async {
    await _show(tester, persist: false);
    expect(find.text('Операция удалена'), findsNothing);
  });

  testWidgets('со скринридером (persist) сообщение не исчезает само', (
    tester,
  ) async {
    await _show(tester, persist: true);
    expect(find.text('Операция удалена'), findsOneWidget);
  });
}
