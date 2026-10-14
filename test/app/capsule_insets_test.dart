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
import 'package:money_app/app/open_and_seed_database.dart';
import 'package:money_app/core/database/app_database.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/data/accounts_repository_impl.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/home/presentation/home_action_bar.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/data/transactions_repository_impl.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../support/fake_id_generator.dart';
import '../support/fixed_clock.dart';
import '../support/in_memory_database.dart';

/// Отступы под капсулой (7.30c) на настоящей базе: на каждой вкладке
/// последнее, что есть в списке, прокручивается выше капсулы.
late AppDatabase _db;

Future<void> _pumpApp(WidgetTester tester, {double textScale = 1}) async {
  tester.view.physicalSize = const Size(393, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final clock = FixedClock(DateTime(2026, 10, 20, 15));
  final settings = AppSettingsController();
  addTearDown(settings.dispose);
  await tester.runAsync(() async {
    _db = await openAndSeedDatabase(
      openInMemoryDatabase,
      idGenerator: FakeIdGenerator(prefix: 'seed'),
      clock: clock,
    );
    addTearDown(_db.close);
    final category =
        await (_db.select(_db.categories)
              ..where((c) => c.kind.equals('expense') & c.parentId.isNull())
              ..limit(1))
            .getSingle();
    final accounts = DriftAccountsRepository(_db, clock: clock);
    for (var i = 0; i < 8; i++) {
      await accounts.create(
        Account(
          id: 'acc-$i',
          name: 'Счёт $i',
          iconKey: 'card',
          openingBalance: Money.fromMinor(10000 * (i + 1), 'RUB'),
          sortOrder: i,
          currencyDigits: 2,
        ),
      );
    }
    final transactions = DriftTransactionsRepository(_db, clock: clock);
    for (var day = 1; day <= 18; day++) {
      await transactions.add(
        Transaction(
          id: 't-$day',
          type: TransactionType.expense,
          amount: Money.fromMinor(1000 + day, 'RUB'),
          occurredOn: DateOnly(2026, 10, day),
          occurredAt: DateTime.utc(2026, 10, day, 9),
          categoryId: category.id,
          note: 'запись $day',
        ),
      );
    }
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: MoneyApp.appLocale,
      supportedLocales: MoneyApp.supportedLocales,
      localizationsDelegates: MoneyApp.localizationsDelegates,
      onGenerateRoute: onGenerateAppRoute,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: AppScopeHost(
        database: _db,
        settings: settings,
        clock: clock,
        idGenerator: FakeIdGenerator(prefix: 'tx'),
        child: BrowseHost(
          child: Builder(
            builder: (context) => AppShell(
              tabs: defaultAppTabs,
              selectedTab: BrowseScope.selectedTabOf(context),
            ),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await _settle(tester);
}

double _capsuleTop(WidgetTester tester) =>
    tester.getTopLeft(find.byType(NavCapsule)).dy;

/// Главный вертикальный список видимой вкладки (самый высокий).
Finder _mainScrollable(WidgetTester tester) {
  final all = find.byType(Scrollable).evaluate().where((e) {
    final state = (e as StatefulElement).state as ScrollableState;
    return state.position.axis == Axis.vertical;
  }).toList();
  all.sort(
    (a, b) => tester
        .getSize(find.byElementPredicate((e) => e == b))
        .height
        .compareTo(
          tester.getSize(find.byElementPredicate((e) => e == a)).height,
        ),
  );
  final top = all.first;
  return find.byElementPredicate((e) => e == top);
}

/// Прокручивает до конца и возвращает нижний край самого нижнего текста.
Future<double> _lowestTextAtEnd(WidgetTester tester) async {
  final scrollable = _mainScrollable(tester);
  final state = tester.state<ScrollableState>(scrollable);
  state.position.jumpTo(state.position.maxScrollExtent);
  await tester.pumpAndSettle();
  final viewport = tester.getRect(scrollable);
  var lowest = 0.0;
  for (final element
      in find
          .descendant(of: scrollable, matching: find.byType(Text))
          .evaluate()) {
    final rect = tester.getRect(find.byElementPredicate((e) => e == element));
    if (rect.top < viewport.bottom && rect.bottom > lowest) {
      lowest = rect.bottom;
    }
  }
  return lowest;
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  for (final tab in ['История', 'Аналитика', 'Баланс', 'Настройки']) {
    testWidgets('«$tab»: последняя строка прокручивается выше капсулы', (
      tester,
    ) async {
      await _pumpApp(tester);
      await _openTab(tester, tab);

      final scrollable = _mainScrollable(tester);
      expect(
        tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
        greaterThan(0),
        reason: 'список длиннее экрана',
      );
      final lowest = await _lowestTextAtEnd(tester);
      expect(lowest, lessThanOrEqualTo(_capsuleTop(tester)));
    });
  }

  testWidgets('«Главная»: кольцо и легенда выше кнопок, кнопки выше капсулы', (
    tester,
  ) async {
    await _pumpApp(tester);
    final bar = tester.getRect(find.byType(HomeActionBar));
    expect(bar.bottom, lessThanOrEqualTo(_capsuleTop(tester)));
    final lowest = await _lowestTextAtEnd(tester);
    expect(lowest, lessThanOrEqualTo(bar.top));
  });

  testWidgets('сообщение «Сохранено … Отменить» — над капсулой', (
    tester,
  ) async {
    await _pumpApp(tester);
    await _openTab(tester, 'Баланс');
    final messenger = ScaffoldMessenger.of(
      tester.element(find.byType(AppShell)),
    );
    messenger.showSnackBar(const SnackBar(content: Text('Сохранено')));
    await tester.pumpAndSettle();
    expect(
      tester
          .getRect(
            find
                .descendant(
                  of: find.byType(SnackBar),
                  matching: find.byType(Material),
                )
                .first,
          )
          .bottom,
      moreOrLessEquals(_capsuleTop(tester) - 8),
    );
  });

  testWidgets('шрифт 200 %, 360 dp: подписи вкладок в одну строку, целиком', (
    tester,
  ) async {
    await _pumpApp(tester, textScale: 2);
    tester.view.physicalSize = const Size(360, 760);
    await tester.pumpAndSettle();
    for (final label in [
      'Главная',
      'История',
      'Аналитика',
      'Баланс',
      'Настройки',
    ]) {
      final text = find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      );
      final rect = tester.getRect(text);
      final capsule = tester.getRect(find.byType(NavCapsule));
      expect(rect.left, greaterThanOrEqualTo(capsule.left), reason: label);
      expect(rect.right, lessThanOrEqualTo(capsule.right), reason: label);
      expect(rect.bottom, lessThanOrEqualTo(capsule.bottom), reason: label);
    }
    expect(tester.takeException(), isNull);
  });
}
