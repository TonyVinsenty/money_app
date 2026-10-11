import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/bar_chart.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/presentation/analytics_controller.dart';
import 'package:money_app/features/analytics/presentation/dynamics_section.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

final _today = DateOnly(2026, 10, 20);
final _nbsp = String.fromCharCode(0x00A0);

Transaction _tx(
  String id,
  int minor,
  DateOnly day, {
  TransactionType type = TransactionType.expense,
}) => Transaction(
  id: id,
  type: type,
  amount: Money.fromMinor(minor, 'RUB'),
  occurredOn: day,
  occurredAt: DateTime.utc(day.year, day.month, day.day, 9),
  categoryId: 'cafe',
);

/// Октябрь: 3-го 1000, 5-го 5400, 12-го 3000 рублей; до 20-го всего 9400 за
/// 20 дней, то есть 470 рублей в день.
final _october = [
  _tx('a', 100000, DateOnly(2026, 10, 3)),
  _tx('b', 540000, DateOnly(2026, 10, 5)),
  _tx('c', 300000, DateOnly(2026, 10, 12)),
];

Future<void> _pump(
  WidgetTester tester, {
  required List<Transaction> transactions,
  AnalyticsPeriod? period,
  TransactionType type = TransactionType.expense,
  ValueChanged<TransactionType>? onType,
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
              transactions: transactions,
              period: period ?? currentPeriod(PeriodKind.month, _today),
              today: _today,
              type: type,
              onTypeSelected: onType,
            ),
          ],
        ),
      ),
    ),
  );
}

String _info(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(DynamicsSection.infoKey)).data!;

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('месяц: заголовок, график и среднее', (tester) async {
    await _pump(tester, transactions: _october);

    expect(find.text('Расходы по дням'), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);
    expect(_info(tester), 'В среднем 470,00$_nbsp₽ в день');
    // Верх шкалы: «круглое» число не меньше 5400 рублей (5400 > 5000, значит 10 000).
    expect(
      tester.widget<BarChart>(find.byType(BarChart)).topLabel,
      '10${_nbsp}000,00$_nbsp₽',
    );
  });

  testWidgets('выбор столбика меняет строку, отпускание возвращает среднее', (
    tester,
  ) async {
    await _pump(tester, transactions: _october);

    final topLeft = tester.getTopLeft(find.byKey(DynamicsSection.chartKey));
    final slot =
        tester.getSize(find.byKey(DynamicsSection.chartKey)).width / 31;
    final gesture = await tester.startGesture(
      topLeft + Offset(slot * 4.5, 100),
    );
    await tester.pump();
    expect(_info(tester), '5 октября: 5${_nbsp}400,00$_nbsp₽');

    await gesture.up();
    await tester.pump();
    expect(_info(tester), 'В среднем 470,00$_nbsp₽ в день');
  });

  testWidgets('подпись для скринридера: период, максимум, среднее', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, transactions: _october);

    expect(
      tester.getSemantics(find.byKey(DynamicsSection.chartKey)).label,
      'Расходы по дням за октябрь. Больше всего 5 октября: 5400 рублей. '
      'В среднем 470 рублей в день',
    );
    handle.dispose();
  });

  testWidgets('год: по месяцам, среднее по прошедшим месяцам', (tester) async {
    await _pump(
      tester,
      transactions: _october,
      period: currentPeriod(PeriodKind.year, _today),
    );

    expect(find.text('Расходы по месяцам'), findsOneWidget);
    // 9400 рублей за 10 месяцев (январь–октябрь) = 940 рублей.
    expect(_info(tester), 'В среднем 940,00$_nbsp₽ в месяц');
  });

  testWidgets('свой длинный период: по месяцам, список с месяцами', (
    tester,
  ) async {
    await _pump(
      tester,
      transactions: [
        _tx('a', 100000, DateOnly(2026, 7, 10)),
        _tx('b', 200000, DateOnly(2026, 9, 10)),
      ],
      period: customPeriod(
        DateOnly(2026, 6, 1),
        DateOnly(2026, 9, 30),
        today: _today,
      ),
    );

    expect(find.text('Расходы по месяцам'), findsOneWidget);
    await tester.tap(find.text('По месяцам'));
    await tester.pumpAndSettle();
    expect(find.text('Июль 2026'), findsOneWidget);
    expect(find.text('Сентябрь 2026'), findsOneWidget);
    expect(find.text('Июнь 2026'), findsNothing);
  });

  testWidgets('вид «День»: пояснение вместо графика', (tester) async {
    await _pump(
      tester,
      transactions: _october,
      period: currentPeriod(PeriodKind.day, _today),
    );

    expect(find.byType(BarChart), findsNothing);
    expect(
      find.text(
        'Выберите неделю, месяц, год или свой период — здесь появятся '
        'столбики по дням',
      ),
      findsOneWidget,
    );
  });

  testWidgets('нет операций выбранного типа: текст вместо графика', (
    tester,
  ) async {
    await _pump(tester, transactions: _october, type: TransactionType.income);

    expect(find.byType(BarChart), findsNothing);
    expect(find.text('За этот период доходов нет'), findsOneWidget);
  });

  testWidgets('список «По дням» свёрнут, внутри только ненулевые дни', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, transactions: _october);

    expect(find.text('3 октября'), findsNothing);
    await tester.tap(find.text('По дням'));
    await tester.pumpAndSettle();

    expect(find.text('3 октября'), findsOneWidget);
    expect(find.text('5 октября'), findsOneWidget);
    expect(find.text('12 октября'), findsOneWidget);
    expect(find.text('4 октября'), findsNothing);
    expect(find.bySemanticsLabel('12 октября, 3000 рублей'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('переключатель типа зовёт колбэк', (tester) async {
    final calls = <TransactionType>[];
    await _pump(tester, transactions: _october, onType: calls.add);

    await tester.tap(find.text('Доходы'));
    expect(calls, [TransactionType.income]);
  });

  testWidgets('360 dp и шрифт 200 %: без переполнения, список раскрывается', (
    tester,
  ) async {
    await _pump(tester, transactions: _october, textScale: 2);
    await tester.tap(find.text('По дням'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('12 октября'), findsOneWidget);
  });

  group('фильтр категории', () {
    Category cat(
      String id,
      String name, {
      bool archived = false,
      bool income = false,
    }) {
      final c = Category.topLevel(
        id: id,
        kind: income ? CategoryKind.income : CategoryKind.expense,
        name: name,
        iconKey: 'icon',
        sortOrder: 0,
      );
      return archived ? c.archived(DateTime.utc(2026, 9, 1)) : c;
    }

    Transaction tx(
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

    final data = [
      tx('a', 100000, DateOnly(2026, 10, 3), 'cafe'),
      tx('b', 300000, DateOnly(2026, 10, 12), 'taxi'),
      tx('c', 50000, DateOnly(2026, 10, 5), 'old'),
      tx(
        'd',
        70000,
        DateOnly(2026, 10, 6),
        'pay',
        type: TransactionType.income,
      ),
    ];
    final cats = [
      cat('cafe', 'Кафе'),
      cat('taxi', 'Такси'),
      cat('old', 'Старое', archived: true),
      cat('dead', 'Мёртвое', archived: true),
      cat('pay', 'Зарплата', income: true),
    ];

    Future<AnalyticsController> pumpFilter(
      WidgetTester tester, {
      double textScale = 1,
    }) async {
      final controller = AnalyticsController(today: _today);
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DynamicsSection(
                    transactions: data,
                    period: currentPeriod(PeriodKind.month, _today),
                    today: _today,
                    type: controller.type,
                    onTypeSelected: controller.selectType,
                    categories: cats,
                    categoryId: controller.categoryId,
                    onCategorySelected: controller.selectCategory,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      return controller;
    }

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.byKey(DynamicsSection.categoryChipKey));
      await tester.pumpAndSettle();
    }

    testWidgets('выбор категории меняет столбики и среднее', (tester) async {
      final controller = await pumpFilter(tester);
      final before = tester.widget<BarChart>(find.byType(BarChart)).weights;
      final infoBefore = _info(tester);

      await openSheet(tester);
      await tester.tap(find.byKey(DynamicsSection.categoryOptionKey('cafe')));
      await tester.pumpAndSettle();

      expect(controller.categoryId, 'cafe');
      expect(find.text('Кафе'), findsOneWidget);
      // 1000 рублей за 20 дней - 50 рублей в день.
      expect(_info(tester), 'В среднем 50,00$_nbsp₽ в день');
      expect(_info(tester), isNot(infoBefore));
      final after = tester.widget<BarChart>(find.byType(BarChart)).weights;
      expect(after, isNot(before));
      expect(after.where((w) => w > 0), [100000]);
    });

    testWidgets(
      'лист: заголовок, «Все категории» первой, отметка у выбранной',
      (tester) async {
        await pumpFilter(tester);
        await openSheet(tester);

        expect(find.text('Категория'), findsOneWidget);
        final all = tester.getTopLeft(
          find.byKey(DynamicsSection.categoryOptionKey(null)),
        );
        final cafe = tester.getTopLeft(
          find.byKey(DynamicsSection.categoryOptionKey('cafe')),
        );
        expect(all.dy, lessThan(cafe.dy));
        expect(
          find.descendant(
            of: find.byKey(DynamicsSection.categoryOptionKey(null)),
            matching: find.byIcon(Icons.check),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('архивная с операциями видна, без операций и доходная — нет', (
      tester,
    ) async {
      await pumpFilter(tester);
      await openSheet(tester);

      expect(
        find.byKey(DynamicsSection.categoryOptionKey('old')),
        findsOneWidget,
      );
      expect(find.text('В архиве'), findsOneWidget);
      expect(
        find.byKey(DynamicsSection.categoryOptionKey('dead')),
        findsNothing,
      );
      expect(
        find.byKey(DynamicsSection.categoryOptionKey('pay')),
        findsNothing,
      );
    });

    testWidgets('смена типа сбрасывает фильтр', (tester) async {
      final controller = await pumpFilter(tester);
      controller.selectCategory('cafe');
      await tester.pump();
      expect(find.text('Кафе'), findsOneWidget);

      await tester.tap(find.text('Доходы'));
      await tester.pump();

      expect(controller.categoryId, isNull);
      expect(find.text('Все категории'), findsOneWidget);
    });

    testWidgets('выбранной нет среди доступных: фильтр не применяется', (
      tester,
    ) async {
      final controller = await pumpFilter(tester);
      final all = _info(tester);
      controller.selectCategory('dead');
      await tester.pump();

      expect(find.text('Все категории'), findsOneWidget);
      expect(_info(tester), all);
    });

    testWidgets('озвучка чипа', (tester) async {
      final handle = tester.ensureSemantics();
      final controller = await pumpFilter(tester);
      expect(
        find.bySemanticsLabel('Фильтр: Все категории, изменить'),
        findsOneWidget,
      );

      controller.selectCategory('cafe');
      await tester.pump();
      expect(find.bySemanticsLabel('Фильтр: Кафе, изменить'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('без колбэка чипа нет', (tester) async {
      await _pump(tester, transactions: _october);
      expect(find.byKey(DynamicsSection.categoryChipKey), findsNothing);
    });

    testWidgets('360 dp и шрифт 200 %: чип и лист без переполнения', (
      tester,
    ) async {
      await pumpFilter(tester, textScale: 2);
      await openSheet(tester);

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(DynamicsSection.categoryOptionKey('taxi')),
        findsOneWidget,
      );
    });
  });
}
