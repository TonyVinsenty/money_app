import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app.dart';

void main() {
  testWidgets('MoneyApp показывает заголовок и заглушку', (tester) async {
    await tester.pumpWidget(const MoneyApp());

    expect(find.text('Money App'), findsOneWidget);
    expect(find.text('Здесь скоро появятся ваши расходы'), findsOneWidget);
  });
}
