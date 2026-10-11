import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/presentation/dynamics_section.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/bar_taps.dart';

final _nbsp = String.fromCharCode(0x00A0);

Transaction _tx(
  String id,
  int minor,
  DateOnly day,
  String category, {
  TransactionType type = TransactionType.expense,
}) => Transaction(
  id: id,
  type: type,
  amount: Money.fromMinor(minor, 'RUB'),
  occurredOn: day,
  occurredAt: DateTime.utc(day.year, day.month, day.day, 9),
  categoryId: category,
);

Category _cat(String id, String name) => Category.topLevel(
  id: id,
  kind: CategoryKind.expense,
  name: name,
  iconKey: 'icon',
  sortOrder: 0,
);

/// Кафе 7000 рублей (3-го) и такси 7000 рублей (5-го): всего 14 000.
final _data = [
  _tx('a', 700000, DateOnly(2026, 10, 3), 'cafe'),
  _tx('b', 700000, DateOnly(2026, 10, 5), 'taxi'),
];

Future<void> _pump(
  WidgetTester tester, {
  required DateOnly today,
  List<Transaction>? transactions,
  AnalyticsPeriod? period,
  TransactionType type = TransactionType.expense,
  String? categoryId,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(360, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DynamicsSection(
              transactions: transactions ?? _data,
              period: period ?? currentPeriod(PeriodKind.month, today),
              today: today,
              type: type,
              categories: [_cat('cafe', 'Кафе'), _cat('taxi', 'Такси')],
              categoryId: categoryId,
              onCategorySelected: (_) {},
            ),
          ],
        ),
      ),
    ),
  );
}

String _forecast(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(DynamicsSection.forecastKey)).data!;

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('6-е число: строки прогноза нет', (tester) async {
    await _pump(tester, today: DateOnly(2026, 10, 6));
    expect(find.byKey(DynamicsSection.forecastKey), findsNothing);
  });

  testWidgets('7-е число: прогноз 14 000 + 2 800 * 24 = 81 200', (
    tester,
  ) async {
    await _pump(tester, today: DateOnly(2026, 10, 7));
    expect(
      _forecast(tester),
      'Если тратить так же, к 31 октября будет ≈ 81${_nbsp}200,00$_nbsp₽',
    );
  });

  testWidgets('среднее и прогноз согласованы (оба с первой операции)', (
    tester,
  ) async {
    await _pump(tester, today: DateOnly(2026, 10, 7));
    // 14 000 за 5 дней (с 3-го по 7-е) -> 2 800 в день на экране.
    expect(
      tester.widget<Text>(find.byKey(DynamicsSection.infoKey)).data,
      'В среднем 2${_nbsp}800,00$_nbsp₽ в день',
    );
    expect(_forecast(tester), contains('81${_nbsp}200,00'));
  });

  testWidgets('прошлый месяц: строки нет', (tester) async {
    await _pump(
      tester,
      today: DateOnly(2026, 10, 20),
      transactions: [_tx('s', 100000, DateOnly(2026, 9, 10), 'cafe')],
      period: currentPeriod(PeriodKind.month, DateOnly(2026, 9, 15)),
    );
    expect(find.byKey(DynamicsSection.chartKey), findsOneWidget);
    expect(find.byKey(DynamicsSection.forecastKey), findsNothing);
  });

  testWidgets('доходы: строки нет', (tester) async {
    await _pump(
      tester,
      today: DateOnly(2026, 10, 20),
      type: TransactionType.income,
      transactions: [
        ..._data,
        _tx(
          'i',
          500000,
          DateOnly(2026, 10, 4),
          'pay',
          type: TransactionType.income,
        ),
      ],
    );
    expect(find.byKey(DynamicsSection.chartKey), findsOneWidget);
    expect(find.byKey(DynamicsSection.forecastKey), findsNothing);
  });

  testWidgets('фильтр категории меняет прогноз', (tester) async {
    await _pump(tester, today: DateOnly(2026, 10, 7), categoryId: 'cafe');
    expect(
      _forecast(tester),
      'Если тратить так же, к 31 октября будет ≈ 40${_nbsp}600,00$_nbsp₽',
    );
  });

  testWidgets('выбранный столбик: прогноз остаётся на месте', (tester) async {
    await _pump(tester, today: DateOnly(2026, 10, 7));
    final before = tester.getTopLeft(find.byKey(DynamicsSection.forecastKey));

    final gesture = await tester.startGesture(
      barSlotPoint(tester, find.byKey(DynamicsSection.chartKey), 2, 31),
    );
    await tester.pump();

    expect(
      tester.widget<Text>(find.byKey(DynamicsSection.infoKey)).data,
      startsWith('3 октября'),
    );
    expect(tester.getTopLeft(find.byKey(DynamicsSection.forecastKey)), before);
    expect(find.byKey(DynamicsSection.forecastKey), findsOneWidget);
    await gesture.up();
  });

  testWidgets('озвучка: «примерно» и сумма словами', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, today: DateOnly(2026, 10, 7));
    expect(
      find.bySemanticsLabel(
        'Если тратить так же, к 31 октября будет примерно 81200 рублей',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('360 dp и 200 %: без переполнения', (tester) async {
    await _pump(tester, today: DateOnly(2026, 10, 7), textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.byKey(DynamicsSection.forecastKey), findsOneWidget);
  });
}
