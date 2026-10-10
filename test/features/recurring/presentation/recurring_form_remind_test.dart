import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/recurring/domain/reminder_plan.dart';
import 'package:money_app/features/recurring/presentation/recurring_form_screen.dart';
import 'package:money_app/features/recurring/presentation/recurring_texts.dart';

import '../../../support/fake_id_generator.dart';
import '../../../support/fixed_clock.dart';
import '../../../support/in_memory_recurring_repository.dart';

final _food = Category.topLevel(
  id: 'food',
  kind: CategoryKind.expense,
  name: 'Еда',
  iconKey: 'tag',
  sortOrder: 0,
);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  late InMemoryRecurringRepository repo;
  late ReminderPermission status;
  late ReminderPermission statusAfterRequest;
  late int requests;

  setUp(() {
    late final InMemoryRecurringRepository r;
    r = InMemoryRecurringRepository(
      FixedClock(DateTime.utc(2026, 10, 10, 12)),
      InMemoryLinkedTransactions(
        (id) => [...r.categories].where((c) => c.id == id).firstOrNull,
      ),
    );
    repo = r..categories.add(_food);
    status = ReminderPermission.notDetermined;
    statusAfterRequest = ReminderPermission.denied;
    requests = 0;
  });

  Future<void> pumpForm(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: RecurringFormScreen(
          currency: currencyInfoFor('RUB'),
          today: DateOnly(2026, 10, 10),
          repository: repo,
          idGenerator: FakeIdGenerator(),
          categories: Stream.value([_food]),
          accounts: Stream.value(const []),
          onPickCategory: (context, type) async =>
              (category: _food, subcategory: null),
          onPickAccount: (context, accounts, selectedId) async => null,
          reminderStatus: () async => status,
          reminderRequest: () async {
            requests++;
            status = statusAfterRequest;
            return status == ReminderPermission.granted;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> toggle(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(RecurringFormScreen.remindKey));
    await tester.tap(find.byKey(RecurringFormScreen.remindKey));
    await tester.pumpAndSettle();
  }

  testWidgets('переключатель включён по умолчанию, пояснения нет', (
    tester,
  ) async {
    await pumpForm(tester);
    final tile = tester.widget<SwitchListTile>(
      find.byKey(RecurringFormScreen.remindKey),
    );
    expect(tile.value, isTrue);
    expect(find.byKey(RecurringFormScreen.remindDeniedKey), findsNothing);
    expect(requests, 0);
  });

  testWidgets('отказ: пояснение словами, повторно система не спрашивается', (
    tester,
  ) async {
    await pumpForm(tester);
    await toggle(tester); // выключили
    await toggle(tester); // включили: первый и единственный запрос
    expect(requests, 1);
    expect(find.text(recurringFormRemindDenied), findsOneWidget);

    await toggle(tester);
    expect(find.byKey(RecurringFormScreen.remindDeniedKey), findsNothing);
    await toggle(tester);
    expect(requests, 1);
    expect(find.text(recurringFormRemindDenied), findsOneWidget);
  });

  testWidgets('уже отказано раньше: пояснение сразу, запроса нет', (
    tester,
  ) async {
    status = ReminderPermission.denied;
    await pumpForm(tester);
    expect(find.text(recurringFormRemindDenied), findsOneWidget);
    expect(requests, 0);
  });

  testWidgets('разрешено: пояснения нет', (tester) async {
    statusAfterRequest = ReminderPermission.granted;
    await pumpForm(tester);
    await toggle(tester);
    await toggle(tester);
    expect(requests, 1);
    expect(find.byKey(RecurringFormScreen.remindDeniedKey), findsNothing);
  });

  testWidgets('флаг сохраняется как выбран, даже при отказе', (tester) async {
    status = ReminderPermission.denied;
    await pumpForm(tester);
    await tester.enterText(
      find.byKey(RecurringFormScreen.nameFieldKey),
      'Интернет',
    );
    await tester.enterText(find.byType(EditableText).last, '650');
    await tester.tap(find.byKey(RecurringFormScreen.categoryKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(RecurringFormScreen.saveKey));
    await tester.pumpAndSettle();
    final items = await tester.runAsync(() => repo.watchAll().first);
    expect(items!.single.payment.remind, isTrue);
  });

  testWidgets('выключенный переключатель сохраняет remind = false', (
    tester,
  ) async {
    await pumpForm(tester);
    await toggle(tester);
    await tester.enterText(
      find.byKey(RecurringFormScreen.nameFieldKey),
      'Интернет',
    );
    await tester.enterText(find.byType(EditableText).last, '650');
    await tester.tap(find.byKey(RecurringFormScreen.categoryKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(RecurringFormScreen.saveKey));
    await tester.pumpAndSettle();
    final items = await tester.runAsync(() => repo.watchAll().first);
    expect(items!.single.payment.remind, isFalse);
    expect(requests, 0);
  });
}
