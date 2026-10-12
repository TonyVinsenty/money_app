import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart' show AppScopeHost;
import 'package:money_app/app/app_shell.dart';
import 'package:money_app/app/app_tabs.dart';
import 'package:money_app/app/browse_scope.dart';
import 'package:money_app/app/notification_open.dart';
import 'package:money_app/app/open_and_seed_database.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/data/accounts_repository_impl.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/categories/data/categories_repository_impl.dart';
import 'package:money_app/features/recurring/data/recurring_repository_impl.dart';
import 'package:money_app/features/recurring/data/reminders_channel.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/presentation/due_section.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../support/fake_id_generator.dart';
import '../support/fixed_clock.dart';
import '../support/in_memory_database.dart';
import '../support/settle_database.dart';

/// Переход ждёт первые данные счетов и «К оплате», потом прокрутку: цепочка
/// чтений из базы в нескольких окнах настоящего времени.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await settleDatabase(tester);
  }
}

/// Натив как на телефоне: флаг тапа сбрасывается при ответе.
class _FakeNative {
  bool tapped = false;
  int asks = 0;
  Future<void> Function(String method)? handler;

  late final channel = RemindersChannel(
    invoke: (method, [arguments]) async {
      if (method != remindersTakeOpenRequestMethod) return null;
      asks++;
      final answer = tapped;
      tapped = false;
      return answer;
    },
    setHandler: (h) => handler = h,
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = false;
  });

  /// Приложение с платежом на сегодня и четырнадцатью счетами: «К оплате»
  /// далеко ниже первого экрана «Баланса» (секция ещё не построена).
  Future<ValueNotifier<int>> pumpApp(
    WidgetTester tester,
    _FakeNative native,
  ) async {
    tester.view.physicalSize = const Size(393, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final clock = FixedClock(DateTime(2026, 10, 10, 12));
    final settings = AppSettingsController();
    addTearDown(settings.dispose);
    late AppDatabase db;
    await tester.runAsync(() async {
      db = await openAndSeedDatabase(
        openInMemoryDatabase,
        idGenerator: FakeIdGenerator(prefix: 'seed'),
        clock: clock,
      );
      addTearDown(db.close);
      final categories = await DriftCategoriesRepository(
        db,
        clock: clock,
      ).watchAll().first;
      final accounts = DriftAccountsRepository(db, clock: clock);
      for (var i = 0; i < 14; i++) {
        await accounts.create(
          Account(
            id: 'acc-$i',
            name: 'Счёт $i',
            iconKey: 'card',
            openingBalance: Money.zero('RUB'),
            sortOrder: i,
            currencyDigits: 2,
          ),
        );
      }
      await DriftRecurringRepository(
        db,
        DriftTransactionsRepository(db, clock: clock),
        clock: clock,
      ).create(
        RecurringPayment(
          id: 'pay-1',
          title: 'Интернет',
          type: TransactionType.expense,
          amount: Money.fromMinor(65000, 'RUB'),
          categoryId: categories.firstWhere((c) => c.name == 'Связь').id,
          unit: RepeatUnit.month,
          every: 1,
          startsOn: DateOnly(2026, 10, 10),
        ),
      );
    });

    late ValueNotifier<int> selectedTab;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        locale: MoneyApp.appLocale,
        supportedLocales: MoneyApp.supportedLocales,
        localizationsDelegates: MoneyApp.localizationsDelegates,
        onGenerateRoute: onGenerateAppRoute,
        home: AppScopeHost(
          database: db,
          settings: settings,
          clock: clock,
          idGenerator: FakeIdGenerator(prefix: 'tx'),
          child: BrowseHost(
            child: NotificationOpenHost(
              channel: native.channel,
              child: Builder(
                builder: (context) => AppShell(
                  tabs: defaultAppTabs,
                  selectedTab: selectedTab = BrowseScope.selectedTabOf(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settleDatabase(tester);
    await tester.pumpAndSettle();
    return selectedTab;
  }

  void resume(WidgetTester tester) {
    for (final s in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(s);
    }
  }

  /// Заголовок «К оплате» на экране, а не только в дереве.
  void expectDueOnScreen(WidgetTester tester) {
    final title = find.byKey(DueSection.titleKey);
    expect(title, findsOneWidget);
    final rect = tester.getRect(title);
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.bottom, lessThanOrEqualTo(700));
  }

  testWidgets('запуск тапом: «Баланс» прокручен к «К оплате»', (tester) async {
    final native = _FakeNative()..tapped = true;
    final tab = await pumpApp(tester, native);
    await settle(tester);
    expect(tab.value, balanceTabIndex);
    expectDueOnScreen(tester);
  });

  testWidgets('без тапа: приложение остаётся на «Главной»', (tester) async {
    final native = _FakeNative();
    final tab = await pumpApp(tester, native);
    expect(native.asks, 1);
    expect(tab.value, 0);
    resume(tester);
    await tester.pumpAndSettle();
    expect(native.asks, 2);
    expect(tab.value, 0);
  });

  testWidgets('тап при открытом приложении (openDue) и повторный вопрос', (
    tester,
  ) async {
    final native = _FakeNative();
    final tab = await pumpApp(tester, native);
    expect(tab.value, 0);
    native.tapped = true;
    await native.handler!(remindersOpenDueMethod);
    await settle(tester);
    expect(tab.value, balanceTabIndex);
    expectDueOnScreen(tester);

    // Пользователь ушёл на «Главную» и вернулся в приложение: флаг уже
    // сброшен, второго перехода нет.
    tab.value = 0;
    await tester.pumpAndSettle();
    resume(tester);
    await tester.pumpAndSettle();
    expect(native.asks, 3);
    expect(tab.value, 0);
  });
}
