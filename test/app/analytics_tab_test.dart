import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/app_services.dart';
import 'package:money_app/app/app_shell.dart';
import 'package:money_app/app/app_tabs.dart';
import 'package:money_app/app/browse_scope.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/period_label.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/donut_chart.dart';
import 'package:money_app/core/ui/period_switcher.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/analytics/domain/period_summary.dart';
import 'package:money_app/features/analytics/presentation/category_breakdown_card.dart';
import 'package:money_app/features/analytics/presentation/category_breakdown_screen.dart';
import 'package:money_app/features/analytics/presentation/period_summary_card.dart';
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

/// Репозиторий «в памяти»: отдаёт операции [data] периода и запоминает, какие
/// периоды у него спрашивали ([requests]).
class _Repo extends FakeTransactionsRepository {
  _Repo([this.data = const []]);

  final List<Transaction> data;
  final List<DateRange> requests = [];

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
    requests.add(period);
    return Stream.value([
      for (final t in data)
        if (period.contains(t.occurredOn)) t,
    ]);
  }
}

Future<void> _pump(
  WidgetTester tester, {
  DateOnly? firstDay,
  _Repo? repo,
  List<Category> categories = const [],
}) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = AppSettingsController();
  addTearDown(settings.dispose);
  repo ??= _Repo();
  repo.firstDay = firstDay;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: MoneyApp.appLocale,
      supportedLocales: MoneyApp.supportedLocales,
      localizationsDelegates: MoneyApp.localizationsDelegates,
      onGenerateRoute: onGenerateAppRoute,
      home: AppScope(
        services: AppServices(
          categories: InMemoryCategoriesRepository(categories),
          transactions: repo,
          settings: settings,
          // Сегодня 4 октября 2026.
          clock: FixedClock(DateTime(2026, 10, 4, 12)),
          idGenerator: FakeIdGenerator(),
        ),
        child: BrowseHost(child: AppShell(tabs: defaultAppTabs)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await _openTab(tester, 'Аналитика');
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
  await tester.pump();
}

Finder get _prev => find.byKey(PeriodSwitcher.previousKey);
Finder get _next => find.byKey(PeriodSwitcher.nextKey);

Finder get _incomeSegment => find.descendant(
  of: find.byKey(CategoryBreakdownCard.typeKey),
  matching: find.text('Доходы'),
);

Transaction _tx(String id, String categoryId, TransactionType type) =>
    Transaction(
      id: id,
      type: type,
      amount: Money.fromMinor(125000, 'RUB'),
      occurredOn: DateOnly(2026, 9, 10),
      occurredAt: DateTime.utc(2026, 9, 10, 9),
      categoryId: categoryId,
    );

final _sept = [
  _tx('a', 'food', TransactionType.expense),
  _tx('b', 'pay', TransactionType.income),
];

final _twoCategories = [
  Category.topLevel(
    id: 'food',
    kind: CategoryKind.expense,
    name: 'Продукты',
    iconKey: 'icon',
    sortOrder: 0,
  ),
  Category.topLevel(
    id: 'pay',
    kind: CategoryKind.income,
    name: 'Зарплата',
    iconKey: 'icon',
    sortOrder: 1,
  ),
];
void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('вкладка «Аналитика»: октябрь 2026, заглушки нет', (
    tester,
  ) async {
    await _pump(tester);

    expect(find.text('Октябрь 2026'), findsOneWidget);
    expect(find.text(tabInDevelopmentLabel), findsNothing);
  });

  testWidgets('«Неделя» показывает подпись недели', (tester) async {
    await _pump(tester);

    await _tap(tester, find.widgetWithText(ChoiceChip, 'Неделя'));

    expect(find.text('28 сентября \u2013 4 октября'), findsOneWidget);
  });

  testWidgets('первая операция в сентябре: «‹» ведёт в сентябрь, дальше нет', (
    tester,
  ) async {
    await _pump(tester, firstDay: DateOnly(2026, 9, 10));

    await _tap(tester, _prev);

    expect(find.text('Сентябрь 2026'), findsOneWidget);
    expect(tester.widget<IconButton>(_prev).onPressed, isNull);
    expect(tester.widget<IconButton>(_next).onPressed, isNotNull);
  });

  testWidgets('без операций стрелки скрыты', (tester) async {
    await _pump(tester);

    expect(_prev, findsNothing);
    expect(_next, findsNothing);
  });

  testWidgets('уход на «Главную» и возврат: период сохранился', (tester) async {
    await _pump(tester, firstDay: DateOnly(2026, 9, 10));
    await _tap(tester, _prev);
    expect(find.text('Сентябрь 2026'), findsOneWidget);

    await _openTab(tester, 'Главная');
    await _openTab(tester, 'Аналитика');

    expect(find.text('Сентябрь 2026'), findsWidgets);
    expect(find.text('Октябрь 2026'), findsNothing);
  });

  testWidgets('смена «сегодня» на 01.11 при текущем месяце: «Ноябрь 2026»', (
    tester,
  ) async {
    await _pump(tester);
    final browse = BrowseScope.of(tester.element(find.byType(AppShell)));

    browse.updateToday(DateOnly(2026, 11, 1));
    await tester.pumpAndSettle();

    expect(find.text('Ноябрь 2026'), findsOneWidget);
  });

  testWidgets('операций нет вообще: приглашение добавить первую', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      find.text(
        'Операций пока нет. Добавьте первую — и здесь появится '
        'статистика',
      ),
      findsOneWidget,
    );
    expect(find.text('За этот период операций нет'), findsNothing);
  });

  testWidgets('пустой период при наличии операций: прежний текст', (
    tester,
  ) async {
    await _pump(tester, firstDay: DateOnly(2026, 9, 10), repo: _Repo(_sept));

    expect(find.text('За этот период операций нет'), findsOneWidget);
    expect(find.textContaining('Операций пока нет'), findsNothing);
  });

  testWidgets('день первой операции пропал на прошлом периоде: стрелок нет', (
    tester,
  ) async {
    final repo = _Repo(_sept);
    await _pump(tester, firstDay: DateOnly(2026, 9, 10), repo: repo);
    await _tap(tester, _prev);
    expect(find.text('Сентябрь 2026'), findsOneWidget);
    expect(_next, findsOneWidget);

    repo.setFirstDay(null);
    await tester.pumpAndSettle();

    expect(_prev, findsNothing);
    expect(_next, findsNothing);
  });

  testWidgets(
    '«Доходы» живут при смене вкладки и периода, запроса не рождают',
    (tester) async {
      final repo = _Repo(_sept);
      await _pump(
        tester,
        firstDay: DateOnly(2026, 9, 10),
        repo: repo,
        categories: _twoCategories,
      );
      await _tap(tester, _prev);
      await tester.pumpAndSettle();
      expect(find.byKey(CategoryBreakdownCard.rowKey('food')), findsOneWidget);

      final before = repo.requests.length;
      await _tap(tester, _incomeSegment);
      await tester.pumpAndSettle();

      expect(repo.requests.length, before);
      expect(find.byKey(CategoryBreakdownCard.rowKey('pay')), findsOneWidget);
      expect(find.byKey(CategoryBreakdownCard.rowKey('food')), findsNothing);

      await _openTab(tester, 'Главная');
      await _openTab(tester, 'Аналитика');
      expect(find.byKey(CategoryBreakdownCard.rowKey('pay')), findsOneWidget);
      expect(find.byKey(CategoryBreakdownCard.rowKey('food')), findsNothing);

      await _tap(tester, _next);
      await tester.pumpAndSettle();
      expect(find.text('Октябрь 2026'), findsOneWidget);

      await _tap(tester, _prev);
      await tester.pumpAndSettle();
      expect(find.byKey(CategoryBreakdownCard.rowKey('pay')), findsOneWidget);
      expect(find.byKey(CategoryBreakdownCard.rowKey('food')), findsNothing);
    },
  );

  testWidgets('месяц с данными, пустой месяц и обратно: кольцо и список '
      'возвращаются', (tester) async {
    await _pump(
      tester,
      firstDay: DateOnly(2026, 8, 1),
      repo: _Repo(_sept),
      categories: _twoCategories,
    );
    await _tap(tester, _prev);
    await tester.pumpAndSettle();
    expect(find.byType(DonutChart), findsOneWidget);
    expect(find.byKey(CategoryBreakdownCard.listKey), findsOneWidget);

    await _tap(tester, _prev);
    await tester.pumpAndSettle();
    expect(find.text('Август 2026'), findsOneWidget);
    expect(find.byType(DonutChart), findsNothing);
    expect(find.text('За этот период операций нет'), findsOneWidget);

    await _tap(tester, _next);
    await tester.pumpAndSettle();
    expect(find.text('Сентябрь 2026'), findsOneWidget);
    expect(find.byType(DonutChart), findsOneWidget);
    expect(find.byKey(CategoryBreakdownCard.listKey), findsOneWidget);
    expect(find.byKey(CategoryBreakdownCard.rowKey('food')), findsOneWidget);
  });

  testWidgets('итоги периода на вкладке: сентябрь с операциями', (
    tester,
  ) async {
    final repo = _Repo([
      Transaction(
        id: 'a',
        type: TransactionType.expense,
        amount: Money.fromMinor(125000, 'RUB'),
        occurredOn: DateOnly(2026, 9, 10),
        occurredAt: DateTime.utc(2026, 9, 10, 9),
        categoryId: 'food',
      ),
    ]);
    await _pump(tester, firstDay: DateOnly(2026, 9, 10), repo: repo);
    expect(find.text('За этот период операций нет'), findsOneWidget);

    await _tap(tester, _prev);
    await tester.pumpAndSettle();

    expect(find.text('Операций: 1'), findsOneWidget);
    expect(
      find.text('\u2212${formatMoney(Money.fromMinor(125000, 'RUB'))}'),
      // «Расходы» и «Баланс» в итогах, центр кольца и строка категории.
      findsNWidgets(4),
    );
  });

  testWidgets('поток периода создаётся один раз и только при смене периода', (
    tester,
  ) async {
    final repo = _Repo();
    await _pump(tester, repo: repo);
    final week = weekRange(DateOnly(2026, 10, 4));
    expect(repo.requests.where((r) => r == week), isEmpty);

    await _tap(tester, find.widgetWithText(ChoiceChip, 'Неделя'));
    expect(repo.requests.where((r) => r == week), hasLength(1));

    // Переключение вкладок и смена фильтра «Истории» поток не пересоздают.
    await _openTab(tester, 'Главная');
    await _openTab(tester, 'Аналитика');
    BrowseScope.of(tester.element(find.byType(AppShell)))
        .setHistorySort(HistorySort.oldestFirst);
    await tester.pumpAndSettle();
    expect(repo.requests.where((r) => r == week), hasLength(1));
  });

  testWidgets('строка категории открывает экран категории за тот же период', (
    tester,
  ) async {
    final repo = _Repo([
      Transaction(
        id: 'a',
        type: TransactionType.expense,
        amount: Money.fromMinor(125000, 'RUB'),
        occurredOn: DateOnly(2026, 9, 10),
        occurredAt: DateTime.utc(2026, 9, 10, 9),
        categoryId: 'food',
      ),
    ]);
    await _pump(
      tester,
      firstDay: DateOnly(2026, 9, 10),
      repo: repo,
      categories: [
        Category.topLevel(
          id: 'food',
          kind: CategoryKind.expense,
          name: 'Продукты',
          iconKey: 'icon',
          sortOrder: 0,
        ),
      ],
    );
    await _tap(tester, _prev);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Продукты'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Продукты'));
    await tester.pumpAndSettle();

    final screen = find.byType(CategoryBreakdownScreen);
    expect(screen, findsOneWidget);
    expect(
      find.descendant(of: screen, matching: find.text('Продукты')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: screen, matching: find.text('Сентябрь 2026')),
      findsOneWidget,
    );
  });

  group('свой интервал', () {
    final all = loadFixtureTransactions();

    Future<void> openSeptemberPicker(WidgetTester tester) async {
      await _pump(tester, firstDay: DateOnly(2026, 9, 1), repo: _Repo(all));
      await _tap(tester, _prev);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Свой'));
      await tester.pumpAndSettle();
    }

    Finder day(String text) => find.descendant(
      of: find.byType(DateRangePickerDialog),
      matching: find.text(text),
    );

    testWidgets(
      'выбор 1\u201315 сентября меняет подпись, итоги и убирает стрелки',
      (tester) async {
        await openSeptemberPicker(tester);

        final dialog = tester.widget<DateRangePickerDialog>(
          find.byType(DateRangePickerDialog),
        );
        expect(dialog.lastDate, DateTime(2026, 10, 4));
        expect(dialog.firstDate, DateTime(2026, 9, 1));
        await tester.tap(day('1').first);
        await tester.pump();
        await tester.tap(day('15').first);
        await tester.pump();
        await tester.tap(find.byType(TextButton).last);
        await tester.pumpAndSettle();

        final range = DateRange(DateOnly(2026, 9, 1), DateOnly(2026, 9, 15));
        expect(
          find.text(
            formatPeriodLabel(
              PeriodKind.custom,
              range,
              today: DateOnly(2026, 10, 4),
            ),
          ),
          findsOneWidget,
        );
        final summary = summarizePeriod(all, range, currency: 'RUB');
        expect(
          find.descendant(
            of: find.byKey(PeriodSummaryCard.expenseKey),
            matching: find.textContaining(formatMoney(summary.expense)),
          ),
          findsOneWidget,
        );
        expect(find.text('Операций: ${summary.count}'), findsOneWidget);
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Свой'))
              .selected,
          isTrue,
        );
        expect(_prev, findsNothing);
        expect(_next, findsNothing);
      },
    );

    testWidgets('отмена оставляет период и выбранный чип', (tester) async {
      await openSeptemberPicker(tester);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Сентябрь 2026'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Месяц'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Свой'))
            .selected,
        isFalse,
      );
    });
  });
}
