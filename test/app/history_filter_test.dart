import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/app_services.dart';
import 'package:money_app/app/app_shell.dart';
import 'package:money_app/app/app_tabs.dart';
import 'package:money_app/app/browse_controller.dart';
import 'package:money_app/app/browse_scope.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/domain/history_view.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../support/fake_id_generator.dart';
import '../support/fakes.dart';
import '../support/fixed_clock.dart';

/// Считает, сколько раз вкладка «История» запрашивала поток операций.
class _Repo extends FakeTransactionsRepository {
  _Repo(this.data);

  final List<Transaction> data;
  int watchCalls = 0;

  @override
  Stream<Money> watchTotal({
    required TransactionType type,
    required DateRange period,
    String currency = 'RUB',
  }) => Stream.value(Money.zero(currency));

  @override
  Stream<List<Transaction>> watchInPeriod(
    DateRange period, {
    String currency = 'RUB',
  }) {
    watchCalls++;
    return Stream.value([
      for (final t in data)
        if (period.contains(t.occurredOn)) t,
    ]);
  }
}

Transaction _tx(String id, DateOnly day, int minor, {String? note}) =>
    Transaction(
      id: id,
      type: TransactionType.expense,
      amount: Money.fromMinor(minor, 'RUB'),
      occurredOn: day,
      occurredAt: DateTime.utc(day.year, day.month, day.day, 9),
      categoryId: 'food',
      note: note,
    );

Future<_Repo> _pumpHistory(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _Repo([
    _tx('a', DateOnly(2026, 10, 2), 10000, note: 'малая'),
    _tx('b', DateOnly(2026, 10, 3), 90000, note: 'большая'),
  ])..firstDay = DateOnly(2026, 10, 2);
  final settings = AppSettingsController();
  addTearDown(settings.dispose);
  final food = Category.topLevel(
    id: 'food',
    kind: CategoryKind.expense,
    name: 'Продукты',
    iconKey: 'icon',
    sortOrder: 0,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: MoneyApp.appLocale,
      supportedLocales: MoneyApp.supportedLocales,
      localizationsDelegates: MoneyApp.localizationsDelegates,
      onGenerateRoute: onGenerateAppRoute,
      home: AppScope(
        services: AppServices(
          categories: InMemoryCategoriesRepository([food]),
          transactions: repo,
          settings: settings,
          clock: FixedClock(DateTime(2026, 10, 4, 12)),
          idGenerator: FakeIdGenerator(),
        ),
        child: BrowseHost(child: AppShell(tabs: defaultAppTabs)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('История'),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

BrowseController _browse(WidgetTester tester) =>
    BrowseScope.of(tester.element(find.byType(AppShell)));

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('смена фильтра и сортировки не пересоздаёт поток; «Сбросить» '
      'выключает только фильтр', (tester) async {
    final repo = await _pumpHistory(tester);
    final calls = repo.watchCalls;
    final browse = _browse(tester);

    browse.setHistorySort(HistorySort.largestFirst);
    browse.setHistoryFilter(HistoryFilter.expenseCategories({'food'}));
    await tester.pumpAndSettle();
    expect(find.text('Фильтр: Расходы · Продукты'), findsOneWidget);
    // По сумме: заголовков дней нет, день во второй строке.
    expect(find.text('Вчера · большая'), findsOneWidget);
    expect(find.text('Вчера'), findsNothing);

    browse.setHistoryFilter(HistoryFilter.expenseCategories({'zzz'}));
    await tester.pumpAndSettle();
    expect(find.text('Ничего не найдено'), findsOneWidget);
    expect(find.text('Операций пока нет'), findsNothing);

    await tester.tap(find.text('Сбросить фильтр'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Фильтр:'), findsNothing);
    expect(browse.historyFilter.isActive, isFalse);
    expect(browse.historySort, HistorySort.largestFirst);
    expect(find.text('Вчера · большая'), findsOneWidget);
    expect(repo.watchCalls, calls);
  });

  testWidgets('кнопка «Сбросить» в полоске выключает фильтр', (tester) async {
    await _pumpHistory(tester);
    final browse = _browse(tester);
    browse.setHistoryFilter(HistoryFilter(type: HistoryTypeFilter.income));
    await tester.pumpAndSettle();
    expect(find.text('Фильтр: Доходы'), findsOneWidget);
    expect(find.text('Ничего не найдено'), findsOneWidget);

    await tester.tap(find.text('Сбросить'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Фильтр:'), findsNothing);
    expect(find.text('большая'), findsOneWidget);
  });
}
