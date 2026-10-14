import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/option_sheet.dart';

void main() {
  Future<void> open(WidgetTester tester, ValueChanged<int?> onResult) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => onResult(
              await showOptionSheet<int>(
                context,
                title: 'Повтор',
                selected: 1,
                items: const [
                  OptionSheetItem(value: 0, title: 'Раз'),
                  OptionSheetItem(
                    value: 1,
                    title: 'Два',
                    subtitle: 'Пояснение',
                  ),
                ],
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows title, subtitle and one check on the selected row', (
    tester,
  ) async {
    await open(tester, (_) {});
    expect(find.text('Повтор'), findsOneWidget);
    expect(find.text('Пояснение'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('tapping a row returns its value', (tester) async {
    int? result;
    await open(tester, (v) => result = v);
    await tester.tap(find.text('Раз'));
    await tester.pumpAndSettle();
    expect(result, 0);
    expect(find.text('Повтор'), findsNothing);
  });

  testWidgets('closing the sheet returns null', (tester) async {
    int? result = 5;
    await open(tester, (v) => result = v);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });
}
