import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/edit/edit_category_picker_screen.dart';

import '../../../../support/fakes.dart';

Future<void> _pump(WidgetTester tester, TransactionType type) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: EditCategoryPickerScreen(
        type: type,
        categories: StreamCategoriesRepository(
          Stream.value(const <Category>[]),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('нет категорий расходов: текст про расходы', (tester) async {
    await _pump(tester, TransactionType.expense);
    await tester.pump();

    expect(find.text('Нет категорий для расходов'), findsOneWidget);
    expect(find.text('Нет категорий для доходов'), findsNothing);
    expect(find.text('Категорий пока нет'), findsNothing);
  });

  testWidgets('нет категорий доходов: текст про доходы', (tester) async {
    await _pump(tester, TransactionType.income);
    await tester.pump();

    expect(find.text('Нет категорий для доходов'), findsOneWidget);
    expect(find.text('Нет категорий для расходов'), findsNothing);
    expect(find.text('Категорий пока нет'), findsNothing);
  });
}
