import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/presentation/account_form_screen.dart';
import 'package:money_app/features/recurring/presentation/recurring_form_screen.dart';

import '../../support/fake_id_generator.dart';
import '../../support/fakes.dart';

/// Поля форм берут рамку из темы, ошибка ввода видна в обеих темах.
void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  final themes = {'светлая': AppTheme.light(), 'тёмная': AppTheme.dark()};

  Future<void> pumpAccountForm(WidgetTester tester, ThemeData theme) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: AccountFormScreen(
          accounts: InMemoryAccountsRepository(),
          idGenerator: FakeIdGenerator(),
          currency: 'RUB',
        ),
      ),
    );
  }

  Future<void> pumpRecurringForm(WidgetTester tester, ThemeData theme) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: RecurringFormScreen(
          currency: currencyInfoFor('RUB'),
          today: DateOnly(2026, 10, 10),
          repository: FakeRecurringRepository(),
          idGenerator: FakeIdGenerator(),
          categories: Stream.value(const []),
          accounts: Stream.value(const []),
          onPickCategory: (context, type) async => null,
          onPickAccount: (context, accounts, selectedId) async => null,
        ),
      ),
    );
  }

  InputDecorator decoratorOf(WidgetTester tester, Key key) =>
      tester.widget<InputDecorator>(
        find.descendant(
          of: find.byKey(key),
          matching: find.byType(InputDecorator),
        ),
      );

  for (final entry in themes.entries) {
    testWidgets('${entry.key} тема: форма счёта - поле в рамке, ошибка видна', (
      tester,
    ) async {
      await pumpAccountForm(tester, entry.value);
      await tester.pump();
      final name = find.descendant(
        of: find.byKey(AccountFormScreen.nameFieldKey),
        matching: find.byType(InputDecorator),
      );
      final context = tester.element(name);
      expect(
        Theme.of(context).inputDecorationTheme.border,
        isA<OutlineInputBorder>(),
      );
      expect(
        decoratorOf(tester, AccountFormScreen.nameFieldKey).decoration.border,
        isA<OutlineInputBorder>(),
      );

      await tester.tap(find.byKey(AccountFormScreen.saveButtonKey));
      await tester.pumpAndSettle();
      final errorText = decoratorOf(
        tester,
        AccountFormScreen.nameFieldKey,
      ).decoration.errorText;
      expect(errorText, isNotNull);
      expect(find.text(errorText!), findsOneWidget);
    });

    testWidgets(
      '${entry.key} тема: форма платежа - поле в рамке, ошибка видна',
      (tester) async {
        await pumpRecurringForm(tester, entry.value);
        final context = tester.element(
          find.byKey(RecurringFormScreen.nameFieldKey),
        );
        expect(
          Theme.of(context).inputDecorationTheme.border,
          isA<OutlineInputBorder>(),
        );
        // Рамка у поля - из темы (OutlineInputBorder).
        expect(
          decoratorOf(
            tester,
            RecurringFormScreen.nameFieldKey,
          ).decoration.border,
          isA<OutlineInputBorder>(),
        );

        await tester.tap(find.byKey(RecurringFormScreen.saveKey));
        await tester.pumpAndSettle();
        final errorText = decoratorOf(
          tester,
          RecurringFormScreen.nameFieldKey,
        ).decoration.errorText;
        expect(errorText, isNotNull);
        expect(find.text(errorText!), findsOneWidget);
      },
    );
  }
}
