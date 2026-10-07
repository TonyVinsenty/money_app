import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/app_services.dart';
import 'package:money_app/app/app_tabs.dart';
import 'package:money_app/app/browse_controller.dart';
import 'package:money_app/app/browse_scope.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/donut_chart.dart';
import 'package:money_app/core/ui/period_switcher.dart';
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
import '../support/fixture_transactions.dart';

/// Репозиторий операций «в памяти» с тем, что нужно «Главной»: итоги и операции
/// периода из списка [data]. Считает вызовы `watch*` и может придержать ответ.
class _Repo extends FakeTransactionsRepository {
  _Repo(this.data);

  final List<Transaction> data;

  /// Сколько раз «Главная» запрашивала потоки (итоги и операции периода).
  int watchCalls = 0;

  /// Пока задан, потоки не отвечают: так видно, что на экране до ответа.
  Completer<void>? hold;

  // Stream.multi: у каждого слушателя свой ответ (как у потоков drift).
  Stream<T> _answer<T>(T Function() compute) =>
      Stream.multi((controller) async {
        final gate = hold;
        if (gate != null) await gate.future;
        controller.add(compute());
      });

  bool _in(Transaction t, DateRange period) => period.contains(t.occurredOn);

  @override
  Stream<Money> watchTotal({
    required TransactionType type,
    required DateRange period,
    String currency = 'RUB',
  }) {
    watchCalls++;
    return _answer(
      () => Money.fromMinor(
        data
            .where((t) => t.type == type && _in(t, period))
            .fold(0, (sum, t) => sum + t.amount.minorUnits),
        currency,
      ),
    );
  }

  @override
  Stream<List<Transaction>> watchInPeriod(
    DateRange period, {
    String currency = 'RUB',
  }) {
    watchCalls++;
    return _answer(
      () => [
        for (final t in data)
          if (_in(t, period)) t,
      ],
    );
  }
}

String _expense(int minor) =>
    '\u2212${formatMoney(Money.fromMinor(minor, 'RUB'))}';
String _income(int minor) => '+${formatMoney(Money.fromMinor(minor, 'RUB'))}';

late BrowseController _browse;

Future<void> _pump(
  WidgetTester tester,
  _Repo repo, {
  Size size = const Size(393, 852),
  double textScale = 1,
  List<Category> categories = const [],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = AppSettingsController();
  addTearDown(settings.dispose);
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
          categories: InMemoryCategoriesRepository(categories),
          transactions: repo,
          settings: settings,
          clock: FixedClock(DateTime(2026, 10, 4, 12)),
          idGenerator: FakeIdGenerator(),
          csvImport: FakeCsvImportStore(),
        ),
        child: BrowseHost(
          child: Builder(
            builder: (context) {
              _browse = BrowseScope.of(context);
              return const Scaffold(body: HomeTab());
            },
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Finder get _prev => find.byKey(PeriodSwitcher.previousKey);
Finder get _next => find.byKey(PeriodSwitcher.nextKey);

bool _enabled(WidgetTester tester, Finder arrow) =>
    tester.widget<IconButton>(arrow).onPressed != null;

Finder _inCard(String key, String text) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: find.text(text));

int _ringWeight(WidgetTester tester) => tester
    .widget<DonutChart>(find.byType(DonutChart))
    .segments
    .fold(0, (sum, s) => sum + s.weight);

Transaction _tx(String id, DateOnly day, int minor) => Transaction(
  id: id,
  type: TransactionType.expense,
  amount: Money.fromMinor(minor, 'RUB'),
  occurredOn: day,
  occurredAt: DateTime.utc(day.year, day.month, day.day, 9),
  categoryId: 'food',
);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  late List<Transaction> fixture;
  late DateOnly firstDay;
  _Repo fixtureRepo() => _Repo(fixture)..firstDay = firstDay;

  setUp(() {
    fixture = loadFixtureTransactions();
    firstDay = fixture.map((t) => t.occurredOn).reduce((a, b) => a < b ? a : b);
  });

  testWidgets('тестовый набор: «‹» показывает сентябрь целиком, «›» возвращает '
      'октябрь', (tester) async {
    expect(firstDay.month, 9, reason: 'набор начинается в сентябре');
    await _pump(tester, fixtureRepo());

    expect(find.text('Октябрь 2026'), findsOneWidget);
    expect(_enabled(tester, _prev), isTrue);
    expect(_enabled(tester, _next), isFalse);
    final octoberRing = _ringWeight(tester);

    await tester.tap(_prev);
    await tester.pump();
    await tester.pump();

    expect(find.text('Сентябрь 2026'), findsOneWidget);
    expect(_inCard('month-summary-expense', _expense(12803388)), findsOne);
    expect(_inCard('month-summary-income', _income(10294900)), findsOne);
    expect(
      find.descendant(
        of: find.byType(DonutChart),
        matching: find.text(_expense(12803388)),
      ),
      findsOneWidget,
    );
    expect(_ringWeight(tester), 12803388);
    expect(_ringWeight(tester), isNot(octoberRing));
    // Месяц первой операции: дальше назад нельзя, вперёд можно.
    expect(_enabled(tester, _prev), isFalse);
    expect(_enabled(tester, _next), isTrue);

    await tester.tap(_next);
    await tester.pump();
    await tester.pump();
    expect(find.text('Октябрь 2026'), findsOneWidget);
    expect(_ringWeight(tester), octoberRing);
  });

  testWidgets('фильтр и сортировка «Истории» не пересоздают потоки «Главной», '
      'смена месяца — пересоздаёт все три', (tester) async {
    final repo = fixtureRepo();
    await _pump(tester, repo);
    final initial = repo.watchCalls;
    expect(initial, 3);

    _browse.setHistoryFilter(HistoryFilter.expenseCategories({'food'}));
    await tester.pump();
    _browse.setHistorySort(HistorySort.largestFirst);
    await tester.pump();
    _browse.resetHistoryFilter();
    await tester.pump();
    expect(repo.watchCalls, initial);

    await tester.tap(_prev);
    await tester.pump();
    expect(repo.watchCalls, initial + 3);
    await tester.pump();
    expect(repo.watchCalls, initial + 3);
  });

  testWidgets('смена месяца: до ответа видны прежние данные, «пусто» не '
      'мелькает', (tester) async {
    final repo = fixtureRepo();
    await _pump(tester, repo);
    final octoberExpense = find.descendant(
      of: find.byKey(const ValueKey('month-summary-expense')),
      matching: find.textContaining('\u2212'),
    );
    final before = tester.widget<Text>(octoberExpense).data;
    expect(before, isNotNull);

    final hold = repo.hold = Completer<void>();
    await tester.tap(_prev);
    await tester.pump();
    await tester.pump();

    // Заголовок уже новый, суммы и кольцо ещё прежние, «пусто» нет.
    expect(find.text('Сентябрь 2026'), findsOneWidget);
    expect(tester.widget<Text>(octoberExpense).data, before);
    expect(find.text('Пока нет'), findsNothing);
    expect(find.byType(DonutChart), findsOneWidget);
    expect(find.textContaining('расходов нет'), findsNothing);

    hold.complete();
    await tester.pump();
    await tester.pump();
    expect(_inCard('month-summary-expense', _expense(12803388)), findsOne);
  });

  testWidgets('пустой прошлый месяц: «За сентябрь 2026 расходов нет»; '
      'пустой текущий: «В этом месяце расходов пока нет»', (tester) async {
    final repo = _Repo([_tx('a', DateOnly(2026, 10, 2), 5000)])
      ..firstDay = DateOnly(2026, 9, 3);
    await _pump(tester, repo);
    expect(find.text('В этом месяце расходов пока нет'), findsNothing);

    await tester.tap(_prev);
    await tester.pump();
    await tester.pump();
    expect(find.text('За сентябрь 2026 расходов нет'), findsOneWidget);
    expect(find.text('В этом месяце расходов пока нет'), findsNothing);
  });

  testWidgets('пустой текущий месяц: прежний текст', (tester) async {
    await _pump(tester, _Repo(const []));
    expect(find.text('В этом месяце расходов пока нет'), findsOneWidget);
    expect(find.textContaining('За '), findsNothing);
    // Операций нет вообще: стрелки скрыты, подпись на месте.
    expect(_prev, findsNothing);
    expect(find.text('Октябрь 2026'), findsOneWidget);
  });

  testWidgets('категория с «Главной» открывается за выбранный месяц', (
    tester,
  ) async {
    final september = fixture.where(
      (t) => t.type == TransactionType.expense && t.occurredOn.month == 9,
    );
    final byCategory = <String, int>{};
    for (final t in september) {
      byCategory.update(
        t.categoryId,
        (sum) => sum + t.amount.minorUnits,
        ifAbsent: () => t.amount.minorUnits,
      );
    }
    final top = byCategory.entries.reduce((a, b) => a.value >= b.value ? a : b);
    final categories = [
      for (final id in fixture.map((t) => t.categoryId).toSet())
        Category.topLevel(
          id: id,
          kind: CategoryKind.expense,
          name: id,
          iconKey: 'icon',
          sortOrder: 0,
        ),
    ];
    await _pump(
      tester,
      fixtureRepo(),
      categories: categories,
      size: const Size(393, 1200),
    );
    await tester.tap(_prev);
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text(top.key).first);
    await tester.pumpAndSettle();

    // Вкладка «История» выбрана, месяц тот же, фильтр по категории.
    final shell = tester.element(find.byType(HomeTab));
    expect(BrowseScope.selectedTabOf(shell).value, historyTabIndex);
    expect(BrowseScope.of(shell).month, monthRange(DateOnly(2026, 9, 1)));
    expect(BrowseScope.of(shell).historyFilter.expenseCategoryIds, {top.key});
  });

  testWidgets('шрифт 200 % на 360 dp: без переполнения', (tester) async {
    await _pump(
      tester,
      fixtureRepo(),
      size: const Size(360, 640),
      textScale: 2,
    );
    await tester.tap(_prev);
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Сентябрь 2026'), findsOneWidget);
  });
}
