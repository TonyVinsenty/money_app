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

/// Операции «в памяти»; считает подписки на поток месяца и на поток всех
/// месяцев, чтобы проверить, что набор букв поток не пересоздаёт.
class _Repo extends FakeTransactionsRepository {
  _Repo(this.data) {
    firstDay = data.map((e) => e.occurredOn).reduce((a, b) => a < b ? a : b);
  }

  final List<Transaction> data;
  int periodListens = 0;
  int allListens = 0;

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
  }) => Stream.multi((controller) {
    periodListens++;
    controller.add([
      for (final t in data)
        if (period.contains(t.occurredOn)) t,
    ]);
  });

  @override
  Stream<List<Transaction>> watchAll({String currency = 'RUB'}) =>
      Stream.multi((controller) {
        allListens++;
        controller.add(List.of(data));
      });
}

final _food = Category.topLevel(
  id: 'food',
  kind: CategoryKind.expense,
  name: 'Продукты',
  iconKey: 'icon',
  sortOrder: 0,
);
final _shop = Category.subcategoryOf(
  id: 'shop',
  parent: _food,
  name: 'Пятёрочка',
  iconKey: 'icon',
  sortOrder: 0,
);
final _salary = Category.topLevel(
  id: 'salary',
  kind: CategoryKind.income,
  name: 'Зарплата',
  iconKey: 'icon',
  sortOrder: 0,
);

Transaction _tx(
  String id,
  DateOnly day, {
  String? note,
  String? subcategoryId,
  TransactionType type = TransactionType.expense,
}) => Transaction(
  id: id,
  type: type,
  amount: Money.fromMinor(10000, 'RUB'),
  occurredOn: day,
  occurredAt: DateTime.utc(day.year, day.month, day.day, 9),
  categoryId: type == TransactionType.income ? 'salary' : 'food',
  subcategoryId: subcategoryId,
  note: note,
);

// Сегодня 4 октября 2026.
List<Transaction> _data() => [
  _tx('oct-coffee', DateOnly(2026, 10, 2), note: 'Кофе с собой'),
  _tx('oct-bread', DateOnly(2026, 10, 3), note: 'хлеб'),
  _tx('aug-tree', DateOnly(2026, 8, 15), note: 'Ёлочные игрушки'),
  _tx('jul-shop', DateOnly(2026, 7, 10), subcategoryId: 'shop'),
  _tx(
    'sep-income',
    DateOnly(2026, 9, 5),
    note: 'кофемашина продана',
    type: TransactionType.income,
  ),
];

Future<_Repo> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = AppSettingsController();
  addTearDown(settings.dispose);
  final repo = _Repo(_data());
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: MoneyApp.appLocale,
      supportedLocales: MoneyApp.supportedLocales,
      localizationsDelegates: MoneyApp.localizationsDelegates,
      onGenerateRoute: onGenerateAppRoute,
      home: AppScope(
        services: AppServices(
          categories: InMemoryCategoriesRepository([_food, _shop, _salary]),
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
  return repo;
}

Future<void> _openTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

Finder get _field =>
    find.widgetWithText(TextField, 'Поиск по комментарию и подкатегории');

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pumpAndSettle();
}

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('без запроса: поле с подсказкой, виден месяц со стрелками', (
    tester,
  ) async {
    await _pump(tester);
    expect(_field, findsOneWidget);
    expect(find.text('Октябрь 2026'), findsOneWidget);
    expect(find.byKey(PeriodSwitcher.previousKey), findsOneWidget);
    expect(find.text('Кофе с собой'), findsOneWidget);
    expect(find.text('Ёлочные игрушки'), findsNothing);
    expect(find.byTooltip('Очистить поиск'), findsNothing);
  });

  testWidgets('поиск идёт во всех месяцах, без регистра и с ё = е; '
      'стрелок нет', (tester) async {
    await _pump(tester);
    await _type(tester, '  ЕЛОЧН ');

    expect(find.text('Во всех месяцах'), findsOneWidget);
    expect(find.text('Октябрь 2026'), findsNothing);
    expect(find.byKey(PeriodSwitcher.previousKey), findsNothing);
    expect(find.byKey(PeriodSwitcher.nextKey), findsNothing);
    expect(find.text('Ёлочные игрушки'), findsOneWidget);
    expect(find.text('Кофе с собой'), findsNothing);
    expect(find.text('хлеб'), findsNothing);
    // Итог найденного.
    expect(find.textContaining('1 операция'), findsOneWidget);
  });

  testWidgets('находит по имени подкатегории', (tester) async {
    await _pump(tester);
    await _type(tester, 'пятерочка');

    expect(find.text('Продукты · Пятёрочка'), findsOneWidget);
    expect(find.text('Кофе с собой'), findsNothing);
  });

  testWidgets('расходы и доходы вместе, итог по обоим', (tester) async {
    await _pump(tester);
    await _type(tester, 'кофе');

    expect(find.text('Кофе с собой'), findsOneWidget);
    expect(find.text('кофемашина продана'), findsOneWidget);
    expect(find.textContaining('2 операции'), findsOneWidget);
  });

  testWidgets('набор букв не пересоздаёт поток; очистка возвращает месяц', (
    tester,
  ) async {
    final repo = await _pump(tester);
    final periodBefore = repo.periodListens;
    await _type(tester, 'к');
    await _type(tester, 'ко');
    await _type(tester, 'коф');
    expect(repo.allListens, 1);
    // Одни пробелы — не поиск: снова месяц.
    await _type(tester, '   ');
    expect(find.text('Октябрь 2026'), findsOneWidget);
    expect(repo.periodListens, periodBefore + 1);

    await _type(tester, 'хлеб');
    expect(repo.allListens, 2);
    await tester.tap(find.byTooltip('Очистить поиск'));
    await tester.pumpAndSettle();
    expect(_fieldText(tester), '');
    expect(find.text('Октябрь 2026'), findsOneWidget);
    expect(find.text('Кофе с собой'), findsOneWidget);
    expect(find.text('хлеб'), findsOneWidget);
  });

  testWidgets('ничего не найдено: текст с запросом и «Очистить поиск»', (
    tester,
  ) async {
    await _pump(tester);
    await _type(tester, ' чай ');

    expect(find.text('Ничего не найдено'), findsOneWidget);
    expect(
      find.text('Нет операций с «чай» в комментарии или подкатегории'),
      findsOneWidget,
    );
    expect(find.text('Сбросить фильтр'), findsNothing);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Очистить поиск'));
    await tester.pumpAndSettle();

    expect(_fieldText(tester), '');
    expect(find.text('Октябрь 2026'), findsOneWidget);
    expect(find.text('Кофе с собой'), findsOneWidget);
  });

  testWidgets('выбранный месяц поиск не меняет', (tester) async {
    await _pump(tester);
    await tester.tap(find.byKey(PeriodSwitcher.previousKey));
    await tester.pumpAndSettle();
    expect(find.text('Сентябрь 2026'), findsOneWidget);

    await _type(tester, 'кофе');
    await tester.tap(find.byTooltip('Очистить поиск'));
    await tester.pumpAndSettle();
    expect(find.text('Сентябрь 2026'), findsOneWidget);
  });

  testWidgets('запрос остаётся после перехода на другую вкладку', (
    tester,
  ) async {
    await _pump(tester);
    await _type(tester, 'ёлоч');
    await _openTab(tester, 'Главная');
    await _openTab(tester, 'История');

    expect(_fieldText(tester), 'ёлоч');
    expect(find.text('Во всех месяцах'), findsOneWidget);
    expect(find.text('Ёлочные игрушки'), findsOneWidget);
  });
}
