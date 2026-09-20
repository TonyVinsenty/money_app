import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/core/money/parse_amount.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/amount_failure_text.dart';
import 'package:money_app/core/ui/amount_field.dart';
import 'package:money_app/core/ui/date_chip.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/quick_add/quick_add_screen.dart';

import '../../../../support/fixed_clock.dart';

/// «Сейчас» в тестах: 20 сентября 2026, местное время.
final _clock = FixedClock(DateTime(2026, 9, 20, 15, 30));

Widget _app(TransactionType type, ThemeMode mode) {
  return MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: mode,
    locale: MoneyApp.appLocale,
    supportedLocales: MoneyApp.supportedLocales,
    localizationsDelegates: MoneyApp.localizationsDelegates,
    home: QuickAddScreen(type: type, clock: _clock),
  );
}

/// День, который сейчас хранит экран: то, что показывает его плашка даты.
DateOnly _screenDay(WidgetTester tester) =>
    tester.widget<DateChip>(find.byType(DateChip)).value;

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

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

  group('плашка даты', () {
    testWidgets('по умолчанию «Сегодня», день экрана — сегодняшний', (
      tester,
    ) async {
      await tester.pumpWidget(_app(TransactionType.expense, ThemeMode.light));

      expect(find.text('Сегодня'), findsOneWidget);
      expect(_screenDay(tester), DateOnly(2026, 9, 20));
    });

    testWidgets(
      'после выбора вчерашнего дня — «Вчера», день хранится экраном',
      (tester) async {
        await tester.pumpWidget(_app(TransactionType.expense, ThemeMode.light));

        await tester.tap(find.byType(DateChip));
        await tester.pumpAndSettle();
        await tester.tap(find.text('19'));
        await tester.tap(find.text('ОК'));
        await tester.pumpAndSettle();

        expect(find.text('Вчера'), findsOneWidget);
        expect(_screenDay(tester), DateOnly(2026, 9, 19));
      },
    );

    testWidgets('завтрашний день в календаре недоступен', (tester) async {
      await tester.pumpWidget(_app(TransactionType.expense, ThemeMode.light));

      await tester.tap(find.byType(DateChip));
      await tester.pumpAndSettle();
      final calendar = tester.widget<CalendarDatePicker>(
        find.byType(CalendarDatePicker),
      );
      expect(calendar.lastDate, DateTime(2026, 9, 20));

      await tester.tap(find.text('21'));
      await tester.tap(find.text('ОК'));
      await tester.pumpAndSettle();

      expect(_screenDay(tester), DateOnly(2026, 9, 20));
    });

    testWidgets('календарь на русском', (tester) async {
      await tester.pumpWidget(_app(TransactionType.expense, ThemeMode.light));

      await tester.tap(find.byType(DateChip));
      await tester.pumpAndSettle();

      expect(find.text('Выберите дату'), findsOneWidget);
      expect(find.text('Отмена'), findsOneWidget);
    });

    testWidgets('«Отмена» оставляет выбранный день как был', (tester) async {
      await tester.pumpWidget(_app(TransactionType.expense, ThemeMode.light));

      await tester.tap(find.byType(DateChip));
      await tester.pumpAndSettle();
      await tester.tap(find.text('19'));
      await tester.tap(find.text('Отмена'));
      await tester.pumpAndSettle();

      expect(_screenDay(tester), DateOnly(2026, 9, 20));
    });
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
