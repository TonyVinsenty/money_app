import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/home/presentation/home_screen.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

Widget _app({
  required void Function(TransactionType) onAdd,
  ThemeMode mode = ThemeMode.light,
  double textScale = 1,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: mode,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(body: HomeScreen(onAddTransaction: onAdd)),
  );
}

/// Кнопка, внутри которой лежит подпись [label].
Finder _button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.bySubtype<FilledButton>(),
);

ButtonStyle _styleOf(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(_button(label)).style!;

/// Отношение контрастности двух цветов (WCAG).
double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

void main() {
  testWidgets('две кнопки с подписями словом и знаками', (tester) async {
    await tester.pumpWidget(_app(onAdd: (_) {}));

    expect(_button('Доход'), findsOneWidget);
    expect(_button('Расход'), findsOneWidget);
    expect(
      find.descendant(of: _button('Доход'), matching: find.byIcon(Icons.add)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _button('Расход'),
        matching: find.byIcon(Icons.remove),
      ),
      findsOneWidget,
    );
  });

  testWidgets('тап вызывает onAddTransaction с нужным типом по разу', (
    tester,
  ) async {
    final calls = <TransactionType>[];
    await tester.pumpWidget(_app(onAdd: calls.add));

    await tester.tap(find.text('Доход'));
    expect(calls, [TransactionType.income]);

    await tester.tap(find.text('Расход'));
    expect(calls, [TransactionType.income, TransactionType.expense]);
  });

  testWidgets('зона нажатия каждой кнопки не меньше 48x48 (высота 56)', (
    tester,
  ) async {
    await tester.pumpWidget(_app(onAdd: (_) {}));

    for (final label in ['Доход', 'Расход']) {
      final size = tester.getSize(_button(label));
      expect(size.width, greaterThanOrEqualTo(48), reason: label);
      expect(size.height, greaterThanOrEqualTo(56), reason: label);
    }
  });

  testWidgets('подписи для скринридера и действие нажатия', (tester) async {
    final semantics = tester.ensureSemantics();
    final calls = <TransactionType>[];
    await tester.pumpWidget(_app(onAdd: calls.add));

    expect(find.bySemanticsLabel('Добавить доход'), findsOneWidget);
    expect(find.bySemanticsLabel('Добавить расход'), findsOneWidget);
    // Скринридер не читает отдельно слово и иконку: только общую подпись.
    expect(find.bySemanticsLabel('Доход'), findsNothing);
    expect(find.bySemanticsLabel('Расход'), findsNothing);

    final node = tester.getSemantics(find.bySemanticsLabel('Добавить расход'));
    expect(node.flagsCollection.isButton, isTrue);
    // Нажатие «как скринридером» (двойной тап) тоже срабатывает.
    tester.semantics.tap(find.semantics.byLabel('Добавить доход'));
    expect(calls, [TransactionType.income]);

    semantics.dispose();
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('цвета кнопок из темы ($mode), контраст текста не ниже 4.5', (
      tester,
    ) async {
      await tester.pumpWidget(_app(onAdd: (_) {}, mode: mode));
      final colors = tester.element(find.byType(HomeScreen)).appColors;
      final surface = Theme.of(tester.element(find.byType(HomeScreen)))
          .colorScheme
          .surface;

      final incomeStyle = _styleOf(tester, 'Доход');
      final expenseStyle = _styleOf(tester, 'Расход');
      expect(incomeStyle.backgroundColor?.resolve({}), colors.income);
      expect(expenseStyle.backgroundColor?.resolve({}), colors.expense);
      expect(
        colors,
        mode == ThemeMode.light ? AppColors.light : AppColors.dark,
      );

      for (final style in [incomeStyle, expenseStyle]) {
        final background = style.backgroundColor!.resolve({})!;
        final foreground = style.foregroundColor!.resolve({})!;
        expect(foreground, surface);
        expect(_contrast(foreground, background), greaterThanOrEqualTo(4.5));
      }
    });
  }

  testWidgets('узкий экран и крупный шрифт: нет переполнения', (tester) async {
    tester.view.physicalSize = const Size(240, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(onAdd: (_) {}, textScale: 2));

    expect(tester.takeException(), isNull);
    expect(find.text('Доход'), findsOneWidget);
    expect(find.text('Расход'), findsOneWidget);
  });
}
