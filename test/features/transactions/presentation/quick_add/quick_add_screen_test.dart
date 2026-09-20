import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/parse_amount.dart';
import 'package:money_app/core/ui/amount_failure_text.dart';
import 'package:money_app/core/ui/amount_field.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/quick_add/quick_add_screen.dart';

Widget _app(TransactionType type, ThemeMode mode) {
  return MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: mode,
    home: QuickAddScreen(type: type),
  );
}

void main() {
  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final type in TransactionType.values) {
      final isIncome = type == TransactionType.income;
      testWidgets('тип $type виден словом, цветом и знаком ($mode)', (
        tester,
      ) async {
        await tester.pumpWidget(_app(type, mode));
        final colors = tester.element(find.byType(QuickAddScreen)).appColors;
        final accent = isIncome ? colors.income : colors.expense;

        // Слово.
        final title = find.text(isIncome ? 'Новый доход' : 'Новый расход');
        expect(title, findsOneWidget);
        expect(
          find.text(isIncome ? 'Новый расход' : 'Новый доход'),
          findsNothing,
        );

        // Цвет: и у слова, и у знака.
        expect(tester.widget<Text>(title).style?.color, accent);
        final icon = find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(isIncome ? Icons.add : Icons.remove),
        );
        // Знак.
        expect(icon, findsOneWidget);
        expect(tester.widget<Icon>(icon).color, accent);
        expect(
          find.descendant(
            of: find.byType(AppBar),
            matching: find.byIcon(isIncome ? Icons.remove : Icons.add),
          ),
          findsNothing,
        );
      });
    }
  }

  testWidgets('скринридер читает заголовок словами, знак не озвучивается', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_app(TransactionType.expense, ThemeMode.light));

    expect(find.bySemanticsLabel('Новый расход'), findsOneWidget);

    semantics.dispose();
  });

  testWidgets('в теле пока временный текст', (tester) async {
    await tester.pumpWidget(_app(TransactionType.income, ThemeMode.light));

    expect(find.text('Здесь появится ввод суммы'), findsOneWidget);
  });

  testWidgets('есть поле суммы со знаком типа операции', (tester) async {
    await tester.pumpWidget(_app(TransactionType.income, ThemeMode.light));
    expect(find.byType(AmountField), findsOneWidget);
    expect(find.text('+'), findsOneWidget);

    await tester.pumpWidget(_app(TransactionType.expense, ThemeMode.light));
    expect(find.text(String.fromCharCode(0x2212)), findsOneWidget);
  });

  testWidgets('кнопка «Далее» видна и по нажатию просит ввести сумму', (
    tester,
  ) async {
    await tester.pumpWidget(_app(TransactionType.expense, ThemeMode.light));
    final message = amountFailureMessage(AmountParseFailure.empty);
    expect(find.text(message), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Далее'));
    await tester.pump();
    expect(find.text(message), findsOneWidget);

    await tester.enterText(find.byType(TextField), '350');
    await tester.pump();
    expect(find.text(message), findsNothing);
  });
}
