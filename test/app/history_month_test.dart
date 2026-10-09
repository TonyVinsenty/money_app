import 'dart:async';

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
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/period_switcher.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../support/fake_id_generator.dart';
import '../support/fakes.dart';
import '../support/fixed_clock.dart';

/// Репозиторий «в памяти»: операции периода из списка [data]; ответ можно
/// придержать ([hold]), а список изменить ([add]) с уведомлением потоков.
class _Repo extends FakeTransactionsRepository {
  _Repo(this.data);

  final List<Transaction> data;
  Completer<void>? hold;
  final _changes = StreamController<void>.broadcast();

  void addLive(Transaction t) {
    data.add(t);
    setFirstDay(data.map((e) => e.occurredOn).reduce((a, b) => a < b ? a : b));
    _changes.add(null);
  }

  // «Главной» нужны и итоги; для этих тестов они не важны.
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
  }) => Stream.multi((controller) async {
    List<Transaction> compute() => [
      for (final t in data)
        if (period.contains(t.occurredOn)) t,
    ];
    final gate = hold;
    if (gate != null) await gate.future;
    controller.add(compute());
    final sub = _changes.stream.listen((_) => controller.add(compute()));
    controller.onCancel = sub.cancel;
  });
}

Transaction _tx(
  String id,
  DateOnly day, {
  int minor = 1000,
  int minute = 0,
  String? note,
}) => Transaction(
  id: id,
  type: TransactionType.expense,
  amount: Money.fromMinor(minor, 'RUB'),
  occurredOn: day,
  occurredAt: DateTime.utc(day.year, day.month, day.day, 9, minute),
  categoryId: 'food',
  note: note,
);

_Repo _repoWith(List<Transaction> data) {
  final repo = _Repo(List.of(data));
  if (data.isNotEmpty) {
    repo.firstDay = data
        .map((e) => e.occurredOn)
        .reduce((a, b) => a < b ? a : b);
  }
  return repo;
}

Future<void> _pump(WidgetTester tester, _Repo repo) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
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
          accounts: FakeAccountsRepository(),
          transfers: FakeTransfersRepository(),
          categories: InMemoryCategoriesRepository([food]),
          transactions: repo,
          settings: settings,
          // Сегодня 4 октября 2026.
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
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Finder get _prev => find.byKey(PeriodSwitcher.previousKey);
Finder get _next => find.byKey(PeriodSwitcher.nextKey);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.tap(finder);
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('месяц общий: листнули на «Главной» — «История» в том же месяце, '
      'и наоборот', (tester) async {
    await _pump(
      tester,
      _repoWith([
        _tx('a', DateOnly(2026, 8, 10)),
        _tx('b', DateOnly(2026, 10, 2)),
      ]),
    );
    await _tap(tester, _prev);
    expect(find.text('Сентябрь 2026'), findsOneWidget);

    await _openTab(tester, 'История');
    expect(find.text('Сентябрь 2026'), findsOneWidget);
    expect(find.text('За сентябрь 2026 операций нет'), findsOneWidget);

    await _tap(tester, _prev);
    expect(find.text('Август 2026'), findsOneWidget);
    expect(find.textContaining('10 августа'), findsOneWidget);

    await _openTab(tester, 'Главная');
    expect(find.text('Август 2026'), findsOneWidget);
  });

  testWidgets('группировка по дням, «Сегодня» и «Вчера», новые сверху', (
    tester,
  ) async {
    await _pump(
      tester,
      _repoWith([
        _tx('old', DateOnly(2026, 10, 3), note: 'вчерашняя'),
        _tx('new', DateOnly(2026, 10, 4), note: 'сегодняшняя'),
        _tx('new2', DateOnly(2026, 10, 4), minute: 5, note: 'вторая'),
        _tx('first', DateOnly(2026, 10, 1), note: 'старая'),
      ]),
    );
    await _openTab(tester, 'История');

    expect(find.text('Сегодня'), findsOneWidget);
    expect(find.text('Вчера'), findsOneWidget);
    double y(String text) => tester.getTopLeft(find.text(text)).dy;
    expect(y('Сегодня'), lessThan(y('вторая')));
    expect(y('вторая'), lessThan(y('сегодняшняя')));
    expect(y('сегодняшняя'), lessThan(y('Вчера')));
    expect(y('Вчера'), lessThan(y('вчерашняя')));
    expect(y('вчерашняя'), lessThan(y('старая')));
  });

  testWidgets('операций нет вообще: прежний текст, переключатель виден', (
    tester,
  ) async {
    await _pump(tester, _repoWith(const []));
    await _openTab(tester, 'История');

    expect(find.text('Операций пока нет'), findsOneWidget);
    expect(find.text('Октябрь 2026'), findsOneWidget);
  });

  testWidgets('месяц пуст, а операции есть: «За … операций нет», стрелки '
      'работают', (tester) async {
    await _pump(tester, _repoWith([_tx('a', DateOnly(2026, 8, 5))]));
    await _openTab(tester, 'История');

    expect(find.text('За октябрь 2026 операций нет'), findsOneWidget);
    expect(find.text('Выберите другой месяц стрелками вверху'), findsOneWidget);
    expect(find.text('Операций пока нет'), findsNothing);
    expect(find.text('Октябрь 2026'), findsOneWidget);

    await _tap(tester, _prev);
    expect(find.text('За сентябрь 2026 операций нет'), findsOneWidget);
    await _tap(tester, _prev);
    expect(find.text('За сентябрь 2026 операций нет'), findsNothing);
    expect(find.text('Продукты'), findsOneWidget);
  });

  testWidgets('в месяце 600 операций: докручиваем до последней', (
    tester,
  ) async {
    final list = [
      for (var i = 0; i < 600; i++)
        _tx(
          't$i',
          DateOnly(2026, 10, 1 + i % 4),
          minute: i ~/ 4,
          note: i == 0 ? 'LAST' : null,
        ),
    ];
    await _pump(tester, _repoWith(list));
    await _openTab(tester, 'История');

    expect(find.text('LAST'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('LAST'),
      400,
      maxScrolls: 500,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('LAST'), findsOneWidget);
    // Переключатель закреплён: остался на месте после прокрутки.
    expect(find.text('Октябрь 2026'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Октябрь 2026')).dy, lessThan(100));
  });

  testWidgets('новая операция сегодняшнего дня появляется сама', (
    tester,
  ) async {
    final repo = _repoWith([_tx('a', DateOnly(2026, 10, 1), note: 'старая')]);
    await _pump(tester, repo);
    await _openTab(tester, 'История');
    expect(find.text('Сегодня'), findsNothing);

    repo.addLive(_tx('b', DateOnly(2026, 10, 4), note: 'свежая'));
    await tester.pumpAndSettle();

    expect(find.text('Сегодня'), findsOneWidget);
    expect(find.text('свежая'), findsOneWidget);
    expect(find.text('старая'), findsOneWidget);
  });

  testWidgets('смена месяца: до ответа видны прежние операции, «пусто» не '
      'мелькает', (tester) async {
    final repo = _repoWith([
      _tx('a', DateOnly(2026, 9, 10), note: 'сентябрьская'),
      _tx('b', DateOnly(2026, 10, 2), note: 'октябрьская'),
    ]);
    await _pump(tester, repo);
    await _openTab(tester, 'История');
    expect(find.text('октябрьская'), findsOneWidget);

    final hold = repo.hold = Completer<void>();
    await _tap(tester, _prev);

    expect(find.text('Сентябрь 2026'), findsOneWidget);
    expect(find.text('октябрьская'), findsOneWidget);
    expect(find.textContaining('операций нет'), findsNothing);
    expect(find.text('Операций пока нет'), findsNothing);

    hold.complete();
    await tester.pump();
    await tester.pump();
    expect(find.text('октябрьская'), findsNothing);
    expect(find.text('сентябрьская'), findsOneWidget);
  });

  testWidgets('скринридер: стрелки подписаны, месяц объявляется', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, _repoWith([_tx('a', DateOnly(2026, 9, 3))]));
    await _openTab(tester, 'История');

    expect(tester.getSemantics(_prev).tooltip, 'Предыдущий месяц');
    expect(tester.getSemantics(_next).tooltip, 'Следующий месяц');
    expect(
      tester.getSemantics(find.text('Октябрь 2026')),
      matchesSemantics(label: 'Октябрь 2026', isLiveRegion: true),
    );
    expect(tester.widget<IconButton>(_next).onPressed, isNull);
    handle.dispose();
  });
}
