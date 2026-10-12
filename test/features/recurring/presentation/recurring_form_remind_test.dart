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

import '../../../support/adaptive_switch.dart';
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
  late int settingsOpened;

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
    settingsOpened = 0;
  });

  Future<void> pumpForm(WidgetTester tester, {TargetPlatform? platform}) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(platform: platform),
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
          openReminderSettings: () async => settingsOpened++,
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

  testWidgets('отказ: «Открыть настройки» видна и открывает настройки', (
    tester,
  ) async {
    status = ReminderPermission.denied;
    await pumpForm(tester);
    final button = find.byKey(RecurringFormScreen.openSettingsKey);
    expect(find.text(recurringFormOpenSettings), findsOneWidget);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(settingsOpened, 1);
    // Тап по кнопке не трогает переключатель.
    expect(find.byKey(RecurringFormScreen.remindDeniedKey), findsOneWidget);
    // Напоминание выключили: ни пояснения, ни кнопки.
    await toggle(tester);
    expect(button, findsNothing);
  });

  testWidgets('разрешено: кнопки нет', (tester) async {
    status = ReminderPermission.granted;
    await pumpForm(tester);
    expect(find.byKey(RecurringFormScreen.openSettingsKey), findsNothing);
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

  for (final (platform, ios) in [
    (TargetPlatform.iOS, true),
    (TargetPlatform.android, false),
  ]) {
    testWidgets('«Напомнить» на $platform: по-айфонному — $ios', (
      tester,
    ) async {
      await pumpForm(tester, platform: platform);
      final inside = find.descendant(
        of: find.byKey(RecurringFormScreen.remindKey),
        matching: find.byType(Switch),
      );
      expect(inside, ios ? paintsIosSwitchTrack : paintsMaterialSwitchTrack);
    });
  }
}
