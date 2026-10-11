import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/account_icons.dart';

Widget _app(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('счёт «Тинькофф» без значка - буква «Т», озвучки у неё нет', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(const AccountIconView('other', name: 'Тинькофф')),
    );

    expect(find.text('Т'), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsNothing);
    expect(find.bySemanticsLabel('Т'), findsNothing);
    handle.dispose();
  });

  testWidgets('неизвестный ключ счёта - тоже «Другое», то есть буква', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const AccountIconView('zzz', name: 'Касса')));

    expect(find.text('К'), findsOneWidget);
  });

  testWidgets('счёт с выбранным значком показывает значок', (tester) async {
    await tester.pumpWidget(
      _app(const AccountIconView('card', name: 'Тинькофф')),
    );

    expect(find.byIcon(Icons.credit_card), findsOneWidget);
    expect(find.text('Т'), findsNothing);
  });

  testWidgets('без названия «Другое» остаётся значком «...»', (tester) async {
    await tester.pumpWidget(_app(const AccountIconView('other')));

    expect(find.byIcon(Icons.more_horiz), findsOneWidget);
  });
}
