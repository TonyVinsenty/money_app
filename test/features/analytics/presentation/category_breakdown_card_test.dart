import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/format/percent_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/category_labels.dart';
import 'package:money_app/core/ui/donut_chart.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/domain/category_totals.dart';
import 'package:money_app/features/analytics/domain/period_summary.dart';
import 'package:money_app/features/analytics/domain/shares.dart';
import 'package:money_app/features/analytics/presentation/analytics_screen.dart';
import 'package:money_app/features/analytics/presentation/category_breakdown_card.dart';
import 'package:money_app/features/analytics/presentation/period_summary_card.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/fixture_transactions.dart';

final _today = DateOnly(2026, 10, 4);
final _september = monthRange(DateOnly(2026, 9, 1));
final String _nbsp = String.fromCharCode(0x00A0);
final String _minus = String.fromCharCode(0x2212);

Money _rub(int minor) => Money.fromMinor(minor, 'RUB');

Category _category(String id, String name, {bool archived = false}) {
  final category = Category.topLevel(
    id: id,
    kind: CategoryKind.expense,
    name: name,
    iconKey: 'icon',
    sortOrder: 0,
  );
  return archived ? category.archived(DateTime.utc(2026, 9, 20)) : category;
}

Transaction _tx(
  String categoryId,
  int minor, {
  TransactionType type = TransactionType.expense,
}) => Transaction(
  id: '$categoryId-$minor-$type',
  type: type,
  amount: _rub(minor),
  occurredOn: DateOnly(2026, 9, 5),
  occurredAt: DateTime.utc(2026, 9, 5, 9),
  categoryId: categoryId,
);

/// Крупные «Продукты» и «Транспорт», две мелкие категории («Кафе», «Кино»)
/// уходят в «Остальное» (2,28 %). Проценты: 65, 33, 1, 1.
final _withOther = [
  _tx('a', 1000000),
  _tx('b', 500000),
  _tx('c', 20000),
  _tx('d', 15000),
];

/// Две мелкие категории меньше 0,2 %: каждая и «Остальное» — «<1 %».
final _belowOne = [
  _tx('a', 1000000),
  _tx('b', 500000),
  _tx('c', 2000),
  _tx('d', 1500),
];

final _categories = [
  _category('a', 'Продукты'),
  _category('b', 'Транспорт'),
  _category('c', 'Кафе'),
  _category('d', 'Кино', archived: true),
];

Future<void> _pump(
  WidgetTester tester, {
  required Stream<PeriodTransactions> transactions,
  List<Category>? categories,
  ValueChanged<Category>? onOpen,
  double textScale = 1,
  double height = 2400,
  bool switchable = false,
}) async {
  tester.view.physicalSize = Size(360, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final categoriesStream = Stream.value(categories ?? _categories);
  var type = TransactionType.expense;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: StatefulBuilder(
        builder: (context, setState) => Scaffold(
          body: AnalyticsScreen(
            period: currentPeriod(PeriodKind.month, DateOnly(2026, 9, 1)),
            today: _today,
            onKindSelected: (_) {},
            onPrevious: null,
            onNext: null,
            transactions: transactions,
            categories: categoriesStream,
            type: type,
            onTypeSelected: switchable
                ? (value) => setState(() => type = value)
                : null,
            onOpenCategory: onOpen,
          ),
        ),
      ),
    ),
  );
  // Два потока вложены друг в друга: данным нужно несколько кадров.
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
}

Stream<PeriodTransactions> _data(List<Transaction> list, [DateRange? range]) =>
    Stream.value((range: range ?? _september, transactions: list));

/// Точка кольца на [turn] оборота по часовой стрелке от «12 часов».
Offset _ringPoint(WidgetTester tester, double turn) {
  final rect = tester.getRect(find.byType(DonutChart));
  final radius = rect.width / 2 - 2 - rect.width * 0.08;
  final angle = turn * 2 * math.pi;
  return rect.center +
      Offset(radius * math.sin(angle), -radius * math.cos(angle));
}

Finder _segment(String label) => find.descendant(
  of: find.byKey(CategoryBreakdownCard.typeKey),
  matching: find.text(label),
);

Finder _row(String id) => find.byKey(CategoryBreakdownCard.rowKey(id));

Finder _inRing(String text) =>
    find.descendant(of: find.byType(DonutChart), matching: find.text(text));

String _pct(int percent, {bool below = false}) =>
    formatPercent(percent, isBelowOne: below);

Color _dotColor(WidgetTester tester, String id) {
  final container = find.descendant(
    of: find.byKey(CategoryBreakdownCard.dotKey(id)),
    matching: find.byType(Container),
  );
  return (tester.widget<Container>(container).decoration! as BoxDecoration)
      .color!;
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('сентябрь тестового набора: все категории расходов, суммы и '
      'проценты', (tester) async {
    final all = loadFixtureTransactions();
    final ids = {for (final t in all) t.categoryId};
    await _pump(
      tester,
      transactions: _data(all),
      categories: [for (final id in ids) _category(id, 'Кат $id')],
    );

    final totals = totalsByCategory(
      all,
      _september,
      type: TransactionType.expense,
      currency: 'RUB',
    );
    expect(totals.length, greaterThan(8));
    var percentSum = 0;
    for (final total in totals) {
      final row = _row(total.categoryId);
      expect(row, findsOneWidget);
      expect(
        find.descendant(
          of: row,
          matching: find.text('$_minus${formatMoney(total.amount)}'),
        ),
        findsOneWidget,
      );
      final percentText = tester
          .widget<Text>(
            find.descendant(of: row, matching: find.byType(Text)).last,
          )
          .data!;
      percentSum += percentText.startsWith('<')
          ? 0
          : int.parse(percentText.split(_nbsp).first);
    }
    expect(percentSum, 100);
    // Кольцо и заголовок на месте.
    expect(find.byKey(CategoryBreakdownCard.typeKey), findsOneWidget);
    expect(find.byType(DonutChart), findsOneWidget);
  });

  testWidgets('«<1 %» у мелких категорий и «Остальное»; метка мелких серая', (
    tester,
  ) async {
    await _pump(tester, transactions: _data(_belowOne));

    expect(
      find.descendant(of: _row('c'), matching: find.text(_pct(0, below: true))),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _row('d'), matching: find.text(_pct(0, below: true))),
      findsOneWidget,
    );
    final colors = AppColors.light;
    expect(_dotColor(tester, 'c'), colors.chartOther);
    expect(_dotColor(tester, 'd'), colors.chartOther);
    expect(_dotColor(tester, 'a'), colors.chartPalette[0]);
    expect(_dotColor(tester, 'b'), colors.chartPalette[1]);
  });

  testWidgets('нажатие на строку зовёт колбэк с категорией', (tester) async {
    final opened = <Category>[];
    await _pump(tester, transactions: _data(_withOther), onOpen: opened.add);

    await tester.tap(_row('b'));
    await tester.pump();

    expect(opened, [_categories[1]]);
  });

  testWidgets('архивная категория показана своим именем и открывается', (
    tester,
  ) async {
    final opened = <Category>[];
    await _pump(tester, transactions: _data(_withOther), onOpen: opened.add);

    expect(
      find.descendant(of: _row('d'), matching: find.text('Кино')),
      findsOneWidget,
    );
    await tester.tap(_row('d'));
    await tester.pump();

    expect(opened.single.id, 'd');
  });

  testWidgets('отпускание пальца на секторе зовёт колбэк', (tester) async {
    final opened = <Category>[];
    await _pump(tester, transactions: _data(_withOther), onOpen: opened.add);

    await tester.tapAt(_ringPoint(tester, 0.3));
    await tester.pump(const Duration(milliseconds: 200));

    expect(opened.map((c) => c.id), ['a']);
  });

  testWidgets('«Остальное»: подсветка без перехода, каждая категория — '
      'строкой', (tester) async {
    final opened = <Category>[];
    await _pump(tester, transactions: _data(_withOther), onOpen: opened.add);

    final gesture = await tester.startGesture(_ringPoint(tester, 0.99));
    await tester.pump();
    expect(_inRing('Остальное'), findsOneWidget);
    expect(_inRing(formatMoney(_rub(35000))), findsOneWidget);
    expect(_inRing(_pct(2)), findsOneWidget);
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));

    expect(opened, isEmpty);
    // «Остальное» в список не попадает, а его категории — отдельными строками.
    expect(find.text('Остальное'), findsNothing);
    await tester.tap(_row('c'));
    await tester.pump();
    expect(opened.map((c) => c.id), ['c']);
  });

  testWidgets('подсветка сектора показывает в центре категорию', (
    tester,
  ) async {
    await _pump(tester, transactions: _data(_withOther));

    final gesture = await tester.startGesture(_ringPoint(tester, 0.3));
    await tester.pump();

    expect(_inRing('Продукты'), findsOneWidget);
    expect(_inRing(formatMoney(_rub(1000000))), findsOneWidget);
    expect(_inRing(_pct(65)), findsOneWidget);
    expect(_inRing('Всего'), findsNothing);
    await gesture.up();
  });

  testWidgets('центр кольца: «Всего» и баланс периода', (tester) async {
    await _pump(
      tester,
      transactions: _data([
        ..._withOther,
        _tx('s', 5000000, type: TransactionType.income),
      ]),
    );

    final balance = summarizePeriod(
      [..._withOther, _tx('s', 5000000, type: TransactionType.income)],
      _september,
      currency: 'RUB',
    ).balance;
    expect(_inRing('Всего'), findsOneWidget);
    expect(_inRing('+${formatMoney(balance)}'), findsOneWidget);
  });

  testWidgets('неизвестная категория: «Без категории», не нажимается', (
    tester,
  ) async {
    final opened = <Category>[];
    await _pump(
      tester,
      transactions: _data([..._withOther, _tx('gone', 700000)]),
      onOpen: opened.add,
    );

    final row = _row('gone');
    expect(
      find.descendant(of: row, matching: find.text(noCategoryLabel)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.byType(InkWell)),
      findsNothing,
    );
    await tester.tap(row);
    await tester.pump();
    expect(opened, isEmpty);
  });

  testWidgets('скринридер читает строку целиком одним узлом, иконку нет', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, transactions: _data(_withOther), onOpen: (_) {});

    final label =
        'Продукты, минус ${spokenMoney(_rub(1000000))}, '
        '${spokenPercent(65, isBelowOne: false)}';
    expect(find.bySemanticsLabel(label), findsOneWidget);
    expect(
      tester.getSemantics(_row('a')),
      isSemantics(label: label, isButton: true),
    );
    // Название, сумма, иконка и метка отдельными узлами не читаются.
    expect(find.bySemanticsLabel('Продукты'), findsNothing);
    expect(find.bySemanticsLabel(formatMoney(_rub(1000000))), findsNothing);
    handle.dispose();
  });

  testWidgets('строка не ниже 48 dp', (tester) async {
    await _pump(tester, transactions: _data(_withOther));

    for (final id in ['a', 'b', 'c', 'd']) {
      expect(tester.getSize(_row(id)).height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('расходов нет, операции есть: текст вместо кольца и списка', (
    tester,
  ) async {
    await _pump(
      tester,
      transactions: _data([_tx('s', 100000, type: TransactionType.income)]),
    );

    expect(find.text('За этот период расходов нет'), findsOneWidget);
    expect(find.byType(PeriodSummaryCard), findsOneWidget);
    expect(find.byType(DonutChart), findsNothing);
    expect(find.byKey(CategoryBreakdownCard.listKey), findsNothing);
  });

  testWidgets('смена периода: до ответа остаются прежние кольцо и список', (
    tester,
  ) async {
    await _pump(tester, transactions: _data(_withOther));
    expect(find.byType(DonutChart), findsOneWidget);

    final next = StreamController<PeriodTransactions>();
    addTearDown(next.close);
    await _pump(tester, transactions: next.stream);

    expect(find.byType(DonutChart), findsOneWidget);
    expect(_row('a'), findsOneWidget);
    expect(find.text('За этот период расходов нет'), findsNothing);
  });

  testWidgets('шрифт 200% на 360 dp: без переполнения', (tester) async {
    final all = loadFixtureTransactions();
    final ids = {for (final t in all) t.categoryId};
    await _pump(
      tester,
      textScale: 2,
      height: 6000,
      transactions: _data(all),
      categories: [for (final id in ids) _category(id, 'Кат $id')],
      onOpen: (_) {},
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(DonutChart), findsOneWidget);
  });

  group('переключатель «Расходы | Доходы»', () {
    final all = loadFixtureTransactions();
    final october = monthRange(DateOnly(2026, 10, 1));
    final ids = {for (final t in all) t.categoryId};
    final cats = [
      for (final id in ids)
        Category.topLevel(
          id: id,
          kind: id.startsWith('inc-')
              ? CategoryKind.income
              : CategoryKind.expense,
          name: 'Кат $id',
          iconKey: 'icon',
          sortOrder: 0,
        ),
    ];

    Future<void> pumpSwitch(
      WidgetTester tester, {
      DateRange? range,
      List<Transaction>? data,
      double textScale = 1,
      ValueChanged<Category>? onOpen,
    }) => _pump(
      tester,
      transactions: _data(data ?? all, range),
      categories: cats,
      switchable: true,
      textScale: textScale,
      onOpen: onOpen,
    );

    Future<void> chooseIncome(WidgetTester tester) async {
      await tester.tap(_segment('Доходы'));
      await tester.pump();
    }

    Set<String> rowIds() => {
      for (final id in ids)
        if (_row(id).evaluate().isNotEmpty) id,
    };

    /// Тексты строки: название, сумма, процент.
    List<String> rowTexts(WidgetTester tester, String id) => [
      for (final t in tester.widgetList<Text>(
        find.descendant(of: _row(id), matching: find.byType(Text)),
      ))
        t.data!,
    ];

    int percentSum(WidgetTester tester) {
      var sum = 0;
      for (final id in rowIds()) {
        final text = rowTexts(tester, id).last;
        sum += text.startsWith('<') ? 0 : int.parse(text.split(_nbsp).first);
      }
      return sum;
    }

    List<CategoryTotal> incomeTotals(DateRange range) => totalsByCategory(
      all,
      range,
      type: TransactionType.income,
      currency: 'RUB',
    );

    testWidgets('по умолчанию расходы; выбранный сегмент отмечен', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpSwitch(tester);

      expect(rowIds().every((id) => id.startsWith('cat-')), isTrue);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Расходы').first),
        isSemantics(isSelected: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Доходы').first),
        isSemantics(isSelected: false),
      );
      handle.dispose();
    });

    testWidgets('«Доходы» меняют и кольцо, и список; обратно — расходы', (
      tester,
    ) async {
      await pumpSwitch(tester);
      final expenseRows = rowIds();
      expect(expenseRows, isNotEmpty);

      await chooseIncome(tester);

      expect(rowIds(), {
        for (final t in incomeTotals(_september)) t.categoryId,
      });
      final donut = tester.widget<DonutChart>(find.byType(DonutChart));
      expect(
        donut.segments.length,
        chartSlices(incomeTotals(_september)).length,
      );
      expect(
        donut.semanticsLabel,
        startsWith('Диаграмма доходов по категориям. Всего: '),
      );

      await tester.tap(_segment('Расходы'));
      await tester.pump();

      expect(rowIds(), expenseRows);
      expect(
        tester.widget<DonutChart>(find.byType(DonutChart)).semanticsLabel,
        startsWith('Диаграмма расходов по категориям. Всего: '),
      );
    });

    testWidgets('доходы за сентябрь: сумма строк 102 949,00, проценты 100', (
      tester,
    ) async {
      await pumpSwitch(tester);
      await chooseIncome(tester);

      expect(
        summarizePeriod(all, _september, currency: 'RUB').income,
        _rub(10294900),
      );
      var minor = 0;
      for (final total in incomeTotals(_september)) {
        expect(
          rowTexts(tester, total.categoryId)[1],
          '+${formatMoney(total.amount)}',
        );
        minor += total.amount.minorUnits;
      }
      expect(minor, 10294900);
      expect(percentSum(tester), 100);
    });

    testWidgets('доходы за октябрь: сумма строк 90 457,00, проценты 100', (
      tester,
    ) async {
      await pumpSwitch(tester, range: october);
      await chooseIncome(tester);

      expect(
        summarizePeriod(all, october, currency: 'RUB').income,
        _rub(9045700),
      );
      var minor = 0;
      for (final total in incomeTotals(october)) {
        expect(
          rowTexts(tester, total.categoryId)[1],
          '+${formatMoney(total.amount)}',
        );
        minor += total.amount.minorUnits;
      }
      expect(minor, 9045700);
      expect(percentSum(tester), 100);
    });

    testWidgets('знак и цвет сумм строк по типу', (tester) async {
      await pumpSwitch(tester);
      Color colorOfRow(String id) => tester
          .widget<Text>(
            find.descendant(of: _row(id), matching: find.byType(Text)).at(1),
          )
          .style!
          .color!;

      expect(colorOfRow('cat-food'), AppColors.light.expense);
      expect(rowTexts(tester, 'cat-food')[1], startsWith(_minus));

      await chooseIncome(tester);

      expect(colorOfRow('inc-salary'), AppColors.light.income);
      expect(rowTexts(tester, 'inc-salary')[1], startsWith('+'));
    });

    testWidgets('озвучка строки: «минус» у расходов, «плюс» у доходов', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpSwitch(tester);
      expect(find.bySemanticsLabel(RegExp(r', минус .*, ')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp(r', плюс .*, ')), findsNothing);

      await chooseIncome(tester);

      expect(find.bySemanticsLabel(RegExp(r', плюс .*, ')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp(r', минус .*, ')), findsNothing);
      handle.dispose();
    });

    testWidgets('карточка итогов при переключении не меняется', (tester) async {
      await pumpSwitch(tester);
      String summaryTexts() => [
        for (final t in tester.widgetList<Text>(
          find.descendant(
            of: find.byType(PeriodSummaryCard),
            matching: find.byType(Text),
          ),
        ))
          t.data,
      ].join('|');
      final before = summaryTexts();
      expect(before, isNotEmpty);

      await chooseIncome(tester);

      expect(summaryTexts(), before);
    });

    testWidgets('центр кольца с доходами — тот же баланс', (tester) async {
      await pumpSwitch(tester);
      final balance = summarizePeriod(all, _september, currency: 'RUB').balance;
      await chooseIncome(tester);

      expect(_inRing(formatMoney(balance)), findsOneWidget);
    });

    testWidgets('период без доходов: текст, переключатель виден и работает', (
      tester,
    ) async {
      await pumpSwitch(tester, data: [_tx('a', 1000000)]);

      await chooseIncome(tester);

      expect(find.text('За этот период доходов нет'), findsOneWidget);
      expect(find.byType(DonutChart), findsNothing);
      expect(find.byKey(CategoryBreakdownCard.typeKey), findsOneWidget);
      expect(find.byType(PeriodSummaryCard), findsOneWidget);

      await tester.tap(_segment('Расходы'));
      await tester.pump();

      expect(find.byType(DonutChart), findsOneWidget);
      expect(find.text('За этот период доходов нет'), findsNothing);
    });

    testWidgets('расходов нет: текст внутри карточки с переключателем', (
      tester,
    ) async {
      await pumpSwitch(
        tester,
        data: [_tx('s', 100000, type: TransactionType.income)],
      );

      expect(find.text('За этот период расходов нет'), findsOneWidget);
      expect(find.byKey(CategoryBreakdownCard.typeKey), findsOneWidget);
    });

    testWidgets('строка дохода открывает категорию', (tester) async {
      final opened = <Category>[];
      await pumpSwitch(tester, onOpen: opened.add);
      await chooseIncome(tester);

      await tester.tap(_row('inc-salary'));
      await tester.pump();

      expect(opened.single.id, 'inc-salary');
    });

    testWidgets('шрифт 200% на 360 dp: без переполнения, с переключателем', (
      tester,
    ) async {
      await pumpSwitch(tester, textScale: 2);
      await chooseIncome(tester);

      expect(tester.takeException(), isNull);
      expect(find.byKey(CategoryBreakdownCard.typeKey), findsOneWidget);
    });
  });
}
