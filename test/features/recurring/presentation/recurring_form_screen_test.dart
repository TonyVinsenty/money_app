import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/balance_tab.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/recurring/presentation/recurring_form_screen.dart';
import 'package:money_app/features/recurring/presentation/recurring_section.dart';
import 'package:money_app/features/recurring/presentation/recurring_texts.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

import '../../../support/fake_id_generator.dart';
import '../../../support/fakes.dart';

Future<void> pumpForm(WidgetTester tester, DateOnly today) async {
  tester.view.physicalSize = const Size(400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: RecurringFormScreen(
        currency: currencyInfoFor('RUB'),
        today: today,
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

Future<void> save(WidgetTester tester) async {
  await tester.tap(find.byKey(RecurringFormScreen.saveKey));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  final today = DateOnly(2026, 10, 10);

  testWidgets('empty form shows name and amount errors', (tester) async {
    await pumpForm(tester, today);
    expect(find.text(recurringFormCategoryHint), findsOneWidget);
    expect(find.text(recurringFormAccountHint), findsOneWidget);
    expect(find.text(recurringFormNoEnd), findsOneWidget);
    await save(tester);
    expect(find.text(recurringErrorEmptyTitle), findsOneWidget);
    expect(find.text('Введите сумму'), findsOneWidget);
  });

  testWidgets('zero amount shows "must be greater than zero"', (tester) async {
    await pumpForm(tester, today);
    await tester.enterText(
      find.byKey(RecurringFormScreen.nameFieldKey),
      'Интернет',
    );
    await tester.enterText(find.byType(EditableText).last, '0');
    await save(tester);
    expect(find.text(recurringErrorEmptyTitle), findsNothing);
    expect(find.text(recurringErrorAmountZero), findsOneWidget);
  });

  testWidgets('valid fields show no errors', (tester) async {
    await pumpForm(tester, today);
    await tester.enterText(
      find.byKey(RecurringFormScreen.nameFieldKey),
      'Интернет',
    );
    await tester.enterText(find.byType(EditableText).last, '650');
    await save(tester);
    expect(find.text(recurringErrorEmptyTitle), findsNothing);
    expect(find.text(recurringErrorAmountZero), findsNothing);
    expect(find.byKey(RecurringFormScreen.endErrorKey), findsNothing);
  });

  testWidgets('first payment cannot be before today', (tester) async {
    await pumpForm(tester, today);
    expect(find.text('Сегодня'), findsOneWidget);
    await tester.tap(find.byKey(RecurringFormScreen.firstKey));
    await tester.pumpAndSettle();
    // 9 октября недоступно: тап ничего не выбирает.
    await tester.tap(find.text('9'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Сегодня'), findsOneWidget);
  });

  testWidgets('end before start shows error', (tester) async {
    await pumpForm(tester, today);
    // Окончание 12 октября, затем первый платёж 20 октября.
    await tester.tap(find.byKey(RecurringFormScreen.endKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('12'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(RecurringFormScreen.firstKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('20'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await save(tester);
    expect(find.text(recurringErrorEndsBeforeStart), findsOneWidget);
    // Убрать окончание - ошибка уходит.
    await tester.tap(find.byKey(RecurringFormScreen.endClearKey));
    await tester.pumpAndSettle();
    expect(find.byKey(RecurringFormScreen.endErrorKey), findsNothing);
    expect(find.text(recurringFormNoEnd), findsOneWidget);
  });

  testWidgets('last-day hint shows only for days 29-31', (tester) async {
    await pumpForm(tester, today);
    expect(find.byKey(RecurringFormScreen.hintKey), findsNothing);
    await tester.tap(find.byKey(RecurringFormScreen.firstKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('31'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text(recurringLastDayHint(31)), findsOneWidget);
    expect(
      find.text('В месяцы, где нет 31-го, — в последний день месяца'),
      findsOneWidget,
    );
  });

  testWidgets('repeat offers six variants', (tester) async {
    await pumpForm(tester, today);
    await tester.tap(find.byKey(RecurringFormScreen.repeatKey));
    await tester.pumpAndSettle();
    for (final o in recurringRepeatOptions) {
      expect(find.text(o.label), findsWidgets);
    }
    expect(recurringRepeatOptions, hasLength(6));
  });

  testWidgets('"Add payment" on Balance opens the form', (tester) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final settings = AppSettingsController();
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        onGenerateRoute: onGenerateAppRoute,
        home: AppScope(
          services: fakeAppServices(settings: settings),
          child: const Scaffold(body: BalanceTab()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.ensureVisible(find.byKey(RecurringSection.addButtonKey));
    await tester.tap(find.byKey(RecurringSection.addButtonKey));
    await tester.pumpAndSettle();
    expect(find.byType(RecurringFormScreen), findsOneWidget);
    expect(find.text(recurringFormTitle), findsOneWidget);
  });
}
