import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/account_avatar.dart';
import 'package:money_app/core/ui/category_avatar.dart';

Widget _app(double scale, Widget child) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(scale)),
    child: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('счёт «Другое»: буква в кружке 40 dp', (tester) async {
    await tester.pumpWidget(
      _app(1, const AccountAvatar('other', name: 'Кариа')),
    );
    expect(find.text('К'), findsOneWidget);
    expect(tester.getSize(find.byType(AccountAvatar)), const Size(40, 40));
    final box = tester.widget<Container>(
      find.descendant(
        of: find.byType(AccountAvatar),
        matching: find.byType(Container),
      ),
    );
    expect((box.decoration! as BoxDecoration).shape, BoxShape.circle);
  });

  for (final (scale, expected) in [(1.0, 40.0), (1.3, 52.0), (2.0, 52.0)]) {
    testWidgets('масштаб шрифта $scale: аватары $expected dp', (tester) async {
      await tester.pumpWidget(
        _app(
          scale,
          const Column(
            children: [AccountAvatar('card'), CategoryAvatar('icon')],
          ),
        ),
      );
      expect(tester.getSize(find.byType(AccountAvatar)).width, expected);
      expect(tester.getSize(find.byType(CategoryAvatar)).width, expected);
    });
  }
}
