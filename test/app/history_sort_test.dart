import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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

class _Repo extends FakeTransactionsRepository {
  _Repo(this.data);

  final List<Transaction> data;

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
  }) => Stream.value([
    for (final t in data)
      if (period.contains(t.occurredOn)) t,
  ]);
}

Transaction _tx(String id, DateOnly day, int minor, String note) => Transaction(
  id: id,
  type: TransactionType.expense,
  amount: Money.fromMinor(minor, 'RUB'),
  occurredOn: day,
  occurredAt: DateTime.utc(day.year, day.month, day.day, 9),
  categoryId: 'food',
  note: note,
);

Future<void> _pump(WidgetTester tester, {double textScale = 1}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _Repo([
    _tx('a', DateOnly(2026, 10, 2), 10000, 'малая'),
    _tx('b', DateOnly(2026, 10, 3), 90000, 'большая'),
    _tx('c', DateOnly(2026, 10, 1), 50000, 'средняя'),
    _tx('d', DateOnly(2026, 9, 5), 1000, 'сентябрьская'),
  ])..firstDay = DateOnly(2026, 9, 5);
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
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: AppScope(
        services: AppServices(
          categories: InMemoryCategoriesRepository([food]),
          transactions: repo,
          settings: settings,
          clock: FixedClock(DateTime(2026, 10, 4, 12)),
          idGenerator: FakeIdGenerator(),
          csvImport: FakeCsvImportStore(),
        ),
        child: BrowseHost(child: AppShell(tabs: defaultAppTabs)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await _openTab(tester, 'История');
}

Future<void> _openTab(WidgetTester tester, String name) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(name)),
  );
  await tester.pumpAndSettle();
}

BrowseController _browse(WidgetTester tester) =>
    BrowseScope.of(tester.element(find.byType(AppShell)));

Future<void> _choose(WidgetTester tester, String label) async {
  await tester.tap(find.bySemanticsLabel(RegExp('^Сортировка:')));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(MenuItemButton, label));
  await tester.pumpAndSettle();
}

/// Заметки в порядке сверху вниз.
List<String> _order(WidgetTester tester) {
  final notes = ['малая', 'большая', 'средняя'];
  final found = [
    for (final n in notes)
      if (find.textContaining(n).evaluate().isNotEmpty) n,
  ];
  found.sort(
    (a, b) => tester
        .getTopLeft(find.textContaining(a))
        .dy
        .compareTo(tester.getTopLeft(find.textContaining(b)).dy),
  );
  return found;
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('каждый вариант меняет порядок', (tester) async {
    await _pump(tester);
    expect(find.text('Сначала новые'), findsOneWidget);
    expect(_order(tester), ['большая', 'малая', 'средняя']);

    await _choose(tester, 'Сначала старые');
    expect(_order(tester), ['средняя', 'малая', 'большая']);
    expect(_browse(tester).historySort, HistorySort.oldestFirst);

    await _choose(tester, 'Сначала крупные');
    expect(_order(tester), ['большая', 'средняя', 'малая']);

    await _choose(tester, 'Сначала мелкие');
    expect(_order(tester), ['малая', 'средняя', 'большая']);

    await _choose(tester, 'Сначала новые');
    expect(_order(tester), ['большая', 'малая', 'средняя']);
  });

  testWidgets('кнопка озвучена, выбранный вариант отмечен', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    expect(find.bySemanticsLabel('Сортировка: сначала новые'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel(RegExp('^Сортировка:')));
    await tester.pumpAndSettle();
    SemanticsNode node(String label) =>
        tester.getSemantics(find.widgetWithText(MenuItemButton, label));
    expect(node('Сначала новые').flagsCollection.isSelected.name, 'isTrue');
    expect(node('Сначала старые').flagsCollection.isSelected.name, 'isFalse');
    expect(find.byIcon(Icons.check), findsOneWidget);
    handle.dispose();
  });

  testWidgets('порядок сохраняется при смене месяца и вкладки', (tester) async {
    await _pump(tester);
    await _choose(tester, 'Сначала крупные');

    _browse(tester).previousMonth();
    await tester.pumpAndSettle();
    expect(find.text('Сначала крупные'), findsOneWidget);
    _browse(tester).nextMonth();
    await tester.pumpAndSettle();

    await _openTab(tester, 'Главная');
    await _openTab(tester, 'История');
    expect(find.text('Сначала крупные'), findsOneWidget);
    expect(_order(tester), ['большая', 'средняя', 'малая']);
  });

  testWidgets('в пустом результате кнопки порядка нет', (tester) async {
    await _pump(tester);
    _browse(tester)
        .setHistoryFilter(HistoryFilter(type: HistoryTypeFilter.income));
    await tester.pumpAndSettle();
    expect(find.text('Ничего не найдено'), findsOneWidget);
    expect(find.text('Сначала новые'), findsNothing);
  });

  testWidgets('шрифт 200 %: кнопка и меню без переполнения, пункты >= 48 dp', (
    tester,
  ) async {
    await _pump(tester, textScale: 2);
    await _choose(tester, 'Сначала мелкие');
    await tester.tap(find.bySemanticsLabel(RegExp('^Сортировка:')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final items = find.byType(MenuItemButton);
    expect(items, findsNWidgets(4));
    for (final e in items.evaluate()) {
      expect(
        tester.getSize(find.byWidget(e.widget)).height,
        greaterThanOrEqualTo(48),
      );
    }
  });
}
