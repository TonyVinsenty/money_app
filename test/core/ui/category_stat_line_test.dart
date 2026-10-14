import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/app_card.dart';
import 'package:money_app/core/ui/category_avatar.dart';
import 'package:money_app/core/ui/category_stat_line.dart';
import 'package:money_app/core/ui/theme/app_spacing.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';

Widget _host({double textScale = 1}) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(
    body: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return AppCard(
            child: CategoryStatLine(
              leading: const CategoryAvatar(null, name: 'Кафе'),
              name: 'Кафе',
              amount: Text('100,00', style: categoryAmountStyle(theme)),
              subtitle: Text('5 %', style: categorySubtitleStyle(theme)),
            ),
          );
        },
      ),
    ),
  ),
);

void main() {
  testWidgets('стили: название bodyLarge, сумма titleMedium 600, '
      'вторая строка bodySmall приглушённо', (tester) async {
    await tester.pumpWidget(_host());
    final theme = Theme.of(tester.element(find.byType(AppCard)));
    final name = tester.widget<Text>(find.text('Кафе'));
    expect(name.style, theme.textTheme.bodyLarge);
    final amount = tester.widget<Text>(find.text('100,00'));
    expect(amount.style?.fontSize, theme.textTheme.titleMedium?.fontSize);
    expect(amount.style?.fontWeight, FontWeight.w600);
    final sub = tester.widget<Text>(find.text('5 %'));
    expect(sub.style?.fontSize, theme.textTheme.bodySmall?.fontSize);
    expect(sub.style?.color, theme.colorScheme.onSurfaceVariant);
  });

  testWidgets('аватар вровень с краем содержимого карточки, сумма справа', (
    tester,
  ) async {
    await tester.pumpWidget(_host());
    final card = tester.getTopLeft(find.byType(AppCard));
    expect(
      tester.getTopLeft(find.byType(CategoryAvatar)).dx,
      card.dx + AppSpacing.l,
    );
    expect(
      tester.getTopLeft(find.text('100,00')).dx,
      greaterThan(tester.getTopRight(find.text('Кафе')).dx),
    );
  });

  testWidgets('крупный шрифт: сумма под названием', (tester) async {
    await tester.pumpWidget(_host(textScale: 1.5));
    expect(
      tester.getTopLeft(find.text('100,00')).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(find.text('Кафе')).dy),
    );
  });
}
