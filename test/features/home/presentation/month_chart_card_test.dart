import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/donut_chart.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/analytics/domain/category_totals.dart';
import 'package:money_app/features/analytics/domain/period_summary.dart';
import 'package:money_app/features/analytics/domain/shares.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/home/presentation/home_action_bar.dart';
import 'package:money_app/features/home/presentation/home_screen.dart';
import 'package:money_app/features/home/presentation/month_chart_card.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/fixture_transactions.dart';

final _month = DateOnly(2026, 9, 20);
final _range = monthRange(_month);
final String _nbsp = String.fromCharCode(0x00A0);

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

Transaction _expense(String categoryId, int minor, {String? id}) {
  return Transaction(
    id: id ?? '$categoryId-$minor',
    type: TransactionType.expense,
    amount: Money.fromMinor(minor, 'RUB'),
    occurredOn: DateOnly(2026, 9, 5),
    occurredAt: DateTime.utc(2026, 9, 5, 9),
    categoryId: categoryId,
  );
}

Transaction _income(int minor) {
  return Transaction(
    id: 'income-$minor',
    type: TransactionType.income,
    amount: Money.fromMinor(minor, 'RUB'),
    occurredOn: DateOnly(2026, 9, 6),
    occurredAt: DateTime.utc(2026, 9, 6, 9),
    categoryId: 'salary',
  );
}

Future<void> _pump(
  WidgetTester tester, {
  Stream<List<Transaction>>? transactions,
  Stream<List<Category>>? categories,
  double textScale = 1,
  double cardHeight = 1000,
  double ringSize = 280,
  double width = 360,
  ThemeMode mode = ThemeMode.light,
  ValueChanged<Set<String>>? onOpen,
  Stream<Money?>? balanceLine,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: mode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: cardHeight,
              child: MonthChartCard(
                transactions: transactions ?? Stream.value(const []),
                categories: categories ?? Stream.value(const []),
                month: _month,
                ringSize: ringSize,
                onOpenCategory: onOpen,
                balanceLine: balanceLine,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  // Два потока вложены друг в друга: данным нужно три кадра.
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
}

/// Тестовый набор: все операции и категории с названиями «Кат» и id.
({List<Transaction> transactions, List<Category> categories}) _fixture() {
  final transactions = loadFixtureTransactions();
  final ids = {for (final t in transactions) t.categoryId};
  return (
    transactions: transactions,
    categories: [for (final id in ids) _category(id, 'Кат $id')],
  );
}

List<ChartSlice> _slices(List<Transaction> transactions) => chartSlices(
  totalsByCategory(
    transactions,
    _range,
    type: TransactionType.expense,
    currency: 'RUB',
  ),
);

String _pct(PercentShare s) =>
    s.isBelowOne ? '<1$_nbsp%' : '${s.percent}$_nbsp%';

String _money(int minor) => formatMoney(Money.fromMinor(minor, 'RUB'));

/// Текст внутри кольца (его центр).
Finder _inRing(String text) =>
    find.descendant(of: find.byType(DonutChart), matching: find.text(text));

/// Легенда: Wrap с элементами под кольцом.
final _legend = find.byType(Wrap);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  testWidgets('заголовок карточки по центру', (tester) async {
    await _pump(tester);
    final title = tester.widget<Text>(find.text('Расходы по категориям'));
    expect(title.textAlign, TextAlign.center);
  });

  test('chartRingSize: резерв под легенду по 28 dp', () {
    final size = chartRingSize(
      viewportWidth: 360,
      viewportHeight: 520,
      textScale: 1,
    );
    // Раньше (строки по 48 dp, зазор 12) здесь получалось 210 dp, потом 238.
    expect(size, 236);
    expect(size, greaterThan(210));
  });
  testWidgets('пустой месяц: серое кольцо, «Всего» и ноль, текст вместо '
      'легенды', (tester) async {
    await _pump(tester);

    expect(find.text('Расходы по категориям'), findsOneWidget);
    expect(find.text('В этом месяце расходов пока нет'), findsOneWidget);
    expect(_inRing('Всего'), findsOneWidget);
    final colors = tester.element(find.byType(MonthChartCard)).appColors;
    // Сумма нейтральная: ни цвет расхода, ни цвет дохода.
    final total = tester.widget<Text>(_inRing(_money(0)));
    expect(total.style?.color, isNot(colors.expense));
    expect(total.style?.color, isNot(colors.income));
    final empty = tester.widget<Text>(
      find.text('В этом месяце расходов пока нет'),
    );
    expect(empty.style?.color, isNot(colors.expense));
  });

  testWidgets('сентябрь тестового набора: всего расходов и проценты легенды', (
    tester,
  ) async {
    final data = _fixture();
    final slices = _slices(data.transactions);
    expect(slices.length, greaterThan(4));
    await _pump(
      tester,
      transactions: Stream.value(data.transactions),
      categories: Stream.value(data.categories),
    );
    await tester.pump();

    // Баланс месяца (доходы минус расходы): знак и цвет по знаку.
    final balance = summarizePeriod(
      data.transactions,
      _range,
      currency: 'RUB',
    ).balance;
    final colors = tester.element(find.byType(MonthChartCard)).appColors;
    final shown = balance.isNegative
        ? formatMoney(balance)
        : '+${formatMoney(balance)}';
    final total = tester.widget<Text>(_inRing(shown));
    expect(
      total.style?.color,
      balance.isNegative ? colors.expense : colors.income,
    );
    expect(
      find.descendant(of: _legend, matching: find.textContaining('₽')),
      findsNothing,
    );

    // Три крупнейших категории: название и процент как в domain.
    for (final slice in slices.take(3)) {
      final id = slice.categoryIds.single;
      expect(find.text('Кат $id'), findsOneWidget);
      expect(
        find.descendant(
          of: find.widgetWithText(Row, 'Кат $id'),
          matching: find.text(_pct(slice.share)),
        ),
        findsOneWidget,
      );
    }
    // Остаток свернут в «Ещё N категорий» с суммарным процентом.
    final rest = slices.skip(3).toList();
    final count = rest.fold<int>(0, (sum, s) => sum + s.categoryIds.length);
    final restPercent = rest.fold<int>(0, (sum, s) => sum + s.share.percent!);
    expect(count, greaterThan(1));
    expect(find.textContaining('Ещё $count '), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(Row, 'Ещё $count категорий'),
        matching: find.text('$restPercent$_nbsp%'),
      ),
      findsOneWidget,
    );
  });

  group('центр: баланс месяца', () {
    Future<Text> center(WidgetTester tester, List<Transaction> list) async {
      await _pump(
        tester,
        transactions: Stream.value(list),
        categories: Stream.value([_category('food', 'Еда')]),
      );
      await tester.pump();
      expect(_inRing('Всего'), findsOneWidget);
      return tester.widget<Text>(
        find.descendant(
          of: find.byType(DonutChart),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Text &&
                w.data != null &&
                w.data!.contains('₽') &&
                w.data != '',
          ),
        ),
      );
    }

    testWidgets('плюс: «+», цвет дохода', (tester) async {
      final text = await center(tester, [_income(5000), _expense('food', 100)]);
      final colors = tester.element(find.byType(MonthChartCard)).appColors;
      expect(text.data, '+${_money(4900)}');
      expect(text.style?.color, colors.income);
    });

    testWidgets('минус: U+2212, цвет расхода', (tester) async {
      final text = await center(tester, [_income(100), _expense('food', 5000)]);
      final colors = tester.element(find.byType(MonthChartCard)).appColors;
      expect(text.data, _money(-4900));
      expect(text.data, startsWith('\u2212'));
      expect(text.style?.color, colors.expense);
    });

    testWidgets('ноль: без знака, нейтрально', (tester) async {
      final text = await center(tester, [_income(100), _expense('food', 100)]);
      final colors = tester.element(find.byType(MonthChartCard)).appColors;
      expect(text.data, _money(0));
      expect(text.style?.color, isNot(colors.expense));
      expect(text.style?.color, isNot(colors.income));
    });

    testWidgets('доход есть, расходов нет: «+», цвет дохода, текст вместо '
        'легенды по центру', (tester) async {
      final text = await center(tester, [_income(1234567)]);
      final colors = tester.element(find.byType(MonthChartCard)).appColors;
      expect(text.data, '+${_money(1234567)}');
      expect(text.style?.color, colors.income);
      expect(find.text('В этом месяце расходов пока нет'), findsOneWidget);
    });
  });

  testWidgets('текст «расходов пока нет» по центру карточки', (tester) async {
    await _pump(tester);
    final card = tester.getRect(find.byType(MonthChartCard));
    final text = tester.getRect(find.text('В этом месяце расходов пока нет'));
    expect((text.center.dx - card.center.dx).abs(), lessThan(1));
  });

  testWidgets('длинная сумма при шрифте 200 % не переполняет дырку кольца', (
    tester,
  ) async {
    await _pump(
      tester,
      transactions: Stream.value([_expense('food', 12803388)]),
      categories: Stream.value([_category('food', 'Еда')]),
      textScale: 2,
      cardHeight: 1400,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    final ring = tester.getRect(find.byType(DonutChart));
    final amount = tester.getRect(_inRing(_money(-12803388)));
    expect(amount.width, lessThanOrEqualTo(ring.width * 0.66 + 0.5));
    expect(ring.contains(amount.topLeft), isTrue);
    expect(ring.contains(amount.bottomRight), isTrue);
  });

  testWidgets('узкий экран 320 dp, шрифт 130 %: центр без overflow', (
    tester,
  ) async {
    await _pump(
      tester,
      transactions: Stream.value([_expense('food', 7340600)]),
      categories: Stream.value([_category('food', 'Еда')]),
      textScale: 1.3,
      cardHeight: 700,
      ringSize: 160,
      width: 320,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    final ring = tester.getRect(find.byType(DonutChart));
    final amount = tester.getRect(_inRing(_money(-7340600)));
    final label = tester.getRect(_inRing('Всего'));
    // Дырка кольца: толщина кольца 16 % стороны, запас 2 dp на край.
    final hole = ring.width * (1 - 2 * 0.16) - 4;
    final centerPoint = ring.center;
    for (final r in [amount, label]) {
      expect(r.width, lessThanOrEqualTo(hole * 0.71 + 0.5));
      // Все углы строки внутри дырки, не на секторах.
      for (final corner in [
        r.topLeft,
        r.bottomRight,
        r.topRight,
        r.bottomLeft,
      ]) {
        expect((corner - centerPoint).distance, lessThan(hole / 2));
      }
    }
  });

  group('строка «Ещё N категорий»', () {
    Future<void> check(
      WidgetTester tester, {
      required List<Transaction> transactions,
      required String label,
    }) async {
      await _pump(
        tester,
        transactions: Stream.value(transactions),
        categories: Stream.value([
          for (final id in {for (final t in transactions) t.categoryId})
            _category(id, 'Кат $id'),
        ]),
        cardHeight: 900,
      );
      await tester.pump();
      expect(find.text(label), findsOneWidget);
      // Легенда не длиннее 4 строк: три категории и «Ещё N».
      expect(find.textContaining('Кат '), findsNWidgets(3));
    }

    // Пять секторов одного размера: в остатке 2 категории.
    testWidgets('2 категории', (tester) async {
      await check(
        tester,
        transactions: [for (var i = 0; i < 5; i++) _expense('c$i', 10000)],
        label: 'Ещё 2 категории',
      );
    });

    // Восемь именных секторов: в остатке 5.
    testWidgets('5 категорий', (tester) async {
      await check(
        tester,
        transactions: [for (var i = 0; i < 8; i++) _expense('c$i', 10000)],
        label: 'Ещё 5 категорий',
      );
    });

    // Восемь именных и 16 мелких (в «Остальном»): 5 + 16 = 21.
    testWidgets('21 категория', (tester) async {
      await check(
        tester,
        transactions: [
          for (var i = 0; i < 8; i++) _expense('c$i', 10000),
          for (var i = 0; i < 16; i++) _expense('t$i', 100),
        ],
        label: 'Ещё 21 категория',
      );
    });
  });

  testWidgets('легенда из 4 секторов целиком, включая «Остальное»', (
    tester,
  ) async {
    // Две крупные категории и две мелкие (меньше 3 %): «Остальное».
    await _pump(
      tester,
      transactions: Stream.value([
        _expense('a', 60000),
        _expense('b', 40000),
        _expense('x', 100),
        _expense('y', 100),
      ]),
      categories: Stream.value([_category('a', 'Еда'), _category('b', 'Дом')]),
    );
    await tester.pump();

    expect(find.text('Еда'), findsOneWidget);
    expect(find.text('Дом'), findsOneWidget);
    expect(find.text('Остальное'), findsOneWidget);
    expect(find.textContaining('Ещё'), findsNothing);
  });

  testWidgets('подсветка сектора меняет центр, отпускание возвращает «Всего»', (
    tester,
  ) async {
    final data = _fixture();
    final first = _slices(data.transactions).first;
    await _pump(
      tester,
      transactions: Stream.value(data.transactions),
      categories: Stream.value(data.categories),
    );
    await tester.pump();
    expect(_inRing('Всего'), findsOneWidget);

    // Точка на кольце сразу правее «12 часов»: там начинается первый сектор.
    final rect = tester.getRect(find.byType(DonutChart));
    final radius = rect.width / 2 - 2 - rect.width * 0.08;
    final gesture = await tester.startGesture(
      Offset(rect.center.dx + 3, rect.center.dy - radius),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(_inRing('Кат ${first.categoryIds.single}'), findsOneWidget);
    expect(_inRing(formatMoney(first.amount)), findsOneWidget);
    expect(_inRing(_pct(first.share)), findsOneWidget);
    expect(_inRing('Всего'), findsNothing);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_inRing('Всего'), findsOneWidget);
  });

  testWidgets('архивная категория показывается своим именем, неизвестная — '
      '«Без категории»', (tester) async {
    await _pump(
      tester,
      transactions: Stream.value([
        _expense('old', 70000),
        _expense('gone', 30000),
      ]),
      categories: Stream.value([_category('old', 'Кино', archived: true)]),
    );
    await tester.pump();

    expect(find.text('Кино'), findsOneWidget);
    expect(find.text('Без категории'), findsOneWidget);
  });

  testWidgets('ошибка потока: текст ошибки, без падения', (tester) async {
    await _pump(tester, transactions: Stream.error(StateError('boom')));
    await tester.pump();
    expect(
      find.text('Не удалось посчитать расходы по категориям'),
      findsOneWidget,
    );
    expect(find.text('В этом месяце расходов пока нет'), findsNothing);
    expect(tester.takeException(), isNull);

    await _pump(tester, categories: Stream.error(StateError('boom')));
    await tester.pump();
    expect(
      find.text('Не удалось посчитать расходы по категориям'),
      findsOneWidget,
    );
  });

  testWidgets('до первого ответа пустое состояние не мигает', (tester) async {
    final controller = StreamController<List<Transaction>>();
    addTearDown(controller.close);
    await _pump(tester, transactions: controller.stream);
    await tester.pump();

    expect(find.text('В этом месяце расходов пока нет'), findsNothing);
    expect(find.text('Всего'), findsNothing);
    expect(find.byType(DonutChart), findsNothing);

    controller.add([_expense('food', 1000)]);
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    expect(find.byType(DonutChart), findsOneWidget);
    expect(find.text('В этом месяце расходов пока нет'), findsNothing);
  });

  group('скринридер', () {
    testWidgets('подпись кольца: месяц и всего расходов', (tester) async {
      final semantics = tester.ensureSemantics();
      final data = _fixture();
      await _pump(
        tester,
        transactions: Stream.value(data.transactions),
        categories: Stream.value(data.categories),
      );
      await tester.pump();
      final balance = summarizePeriod(
        data.transactions,
        _range,
        currency: 'RUB',
      ).balance;
      final spoken = balance.isNegative
          ? spokenMoney(balance)
          : 'плюс ${spokenMoney(balance)}';
      expect(
        find.bySemanticsLabel('Диаграмма расходов за сентябрь. Всего: $spoken'),
        findsOneWidget,
      );

      await _pump(
        tester,
        transactions: Stream.value([_income(1234567), _expense('food', 100)]),
      );
      await tester.pump();
      expect(
        find.bySemanticsLabel(
          'Диаграмма расходов за сентябрь. Всего: '
          'плюс ${spokenMoney(Money.fromMinor(1234467, 'RUB'))}',
        ),
        findsOneWidget,
      );

      await _pump(tester, transactions: Stream.value([_expense('food', 5000)]));
      await tester.pump();
      expect(
        find.bySemanticsLabel(
          'Диаграмма расходов за сентябрь. Всего: '
          '${spokenMoney(Money.fromMinor(-5000, 'RUB'))}',
        ),
        findsOneWidget,
      );

      await _pump(tester);
      await tester.pump();
      expect(
        find.bySemanticsLabel(
          'Диаграмма расходов за сентябрь. Всего: 0 рублей',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('строка легенды читается целиком, метка цвета молчит', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      // 1 234 567 из 3 631 000 копеек: ровно 34 %, остальные 66 %.
      await _pump(
        tester,
        transactions: Stream.value([
          _expense('a', 1234567),
          _expense('b', 2396433),
          _expense('c', 1),
        ]),
        categories: Stream.value([
          _category('a', 'Продукты'),
          _category('b', 'Транспорт'),
          _category('c', 'Мелочь'),
        ]),
      );
      await tester.pump();

      expect(
        find.bySemanticsLabel('Продукты, 12345 рублей 67 копеек, 34 процента'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Транспорт, 23964 рубля 33 копейки, 66 процентов',
        ),
        findsOneWidget,
      );
      // Мелкая доля читается словами.
      expect(
        find.bySemanticsLabel('Мелочь, 0 рублей 1 копейка, меньше 1 процента'),
        findsOneWidget,
      );
      // Название и сумма отдельными узлами не читаются.
      expect(find.bySemanticsLabel('Продукты'), findsNothing);
      semantics.dispose();
    });

    testWidgets('«Ещё N категорий» читается с суммой и процентом', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final transactions = [for (var i = 0; i < 8; i++) _expense('c$i', 10000)];
      final rest = _slices(transactions).skip(3);
      // 8 равных долей: 12 или 13 %, пять последних дают 61 %.
      expect(rest.fold<int>(0, (sum, s) => sum + s.share.percent!), 61);
      await _pump(
        tester,
        transactions: Stream.value(transactions),
        cardHeight: 900,
      );
      await tester.pump();

      expect(
        find.bySemanticsLabel('Ещё 5 категорий, 500 рублей, 61 процент'),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  /// «Главная» целиком на экране [size] с данными [data] и шрифтом [scale].
  Future<void> pumpHome(
    WidgetTester tester,
    Size size, {
    double scale = 1,
    List<Transaction>? transactions,
    List<Category>? categories,
  }) async {
    final data = _fixture();
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: HomeScreen(
            monthExpenses: Stream.value(Money.fromMinor(12803388, 'RUB')),
            monthIncome: Stream.value(Money.fromMinor(10294900, 'RUB')),
            monthTransactions: Stream.value(transactions ?? data.transactions),
            categories: Stream.value(categories ?? data.categories),
            month: _month,
            onOpenCategory: (_) {},
          ),
          bottomNavigationBar: HomeActionBar(onAddTransaction: (_) {}),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  group('раскладка', () {
    final transactions = [
      _expense('a', 5000),
      _expense('b', 3000),
      _expense('c', 2000),
    ];
    final categories = [
      _category('a', 'Продукты'),
      _category('b', 'Транспорт'),
      _category('c', 'Кафе'),
    ];

    // Как у пользователя: четыре элемента легенды в две строки.
    final fiveCategories = [
      for (final id in ['a', 'b', 'c', 'd', 'e']) _expense(id, 10000),
    ];
    final fiveNames = [
      _category('a', 'Продукты'),
      _category('b', 'Транспорт'),
      _category('c', 'Кафе'),
      _category('d', 'Дом'),
      _category('e', 'Одежда'),
    ];
    for (final size in [const Size(411, 914), const Size(360, 640)]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('«Главная» $size, шрифт $scale: без переполнения', (
          tester,
        ) async {
          await pumpHome(
            tester,
            size,
            scale: scale,
            transactions: fiveCategories,
            categories: fiveNames,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets(
      '«Главная» 411 x 914: кольцо крупное, легенда у низа карточки',
      (tester) async {
        await pumpHome(
          tester,
          const Size(411, 914),
          transactions: fiveCategories,
          categories: fiveNames,
        );
        expect(tester.takeException(), isNull);

        final ring = tester.getRect(find.byType(DonutChart));
        final card = tester.getRect(find.byType(MonthChartCard));
        final legend = tester.getRect(find.byType(Wrap));
        // Ширина карточки 379, отступы 16: кольцо упирается в 347 (раньше 315).
        expect(ring.width, greaterThanOrEqualTo(330));
        // Легенда прижата к низу: до края карточки только её отступ 16 dp.
        expect(card.bottom - legend.bottom, lessThanOrEqualTo(16 + 8));
        expect(legend.top, greaterThanOrEqualTo(ring.bottom));
      },
    );

    testWidgets('«Главная» 411 x 700: кольцо забирает всё место по высоте', (
      tester,
    ) async {
      await pumpHome(
        tester,
        const Size(411, 700),
        transactions: fiveCategories,
        categories: fiveNames,
      );
      final ring = tester.getRect(find.byType(DonutChart));
      final card = tester.getRect(find.byType(MonthChartCard));
      final title = tester.getRect(find.text('Расходы по категориям'));
      final legend = tester.getRect(find.byType(Wrap));
      expect(ring.width, 304);
      // Пустоты нет: зазоры над кольцом 12 и под ним 8, отступ снизу 16.
      expect(ring.top - title.bottom, lessThanOrEqualTo(16));
      expect(legend.top - ring.bottom, lessThanOrEqualTo(12));
      expect(card.bottom - legend.bottom, 16);
    });
    for (final width in [360.0, 393.0]) {
      testWidgets('«Главная» $width x 800: кольцо не меньше 250 dp, легенда '
          'под ним', (tester) async {
        await pumpHome(
          tester,
          Size(width, 800),
          transactions: transactions,
          categories: categories,
        );

        final ring = tester.getRect(find.byType(DonutChart));
        expect(ring.width, greaterThanOrEqualTo(250));
        expect(ring.width, lessThanOrEqualTo(360));
        for (final name in ['Продукты', 'Транспорт', 'Кафе']) {
          expect(
            tester.getRect(find.text(name)).top,
            greaterThanOrEqualTo(ring.bottom),
            reason: name,
          );
        }
        // Элементы легенды: компактные, 28 dp, видимых сумм нет, проценты верные.
        for (final pair in {
          'Продукты': 50,
          'Транспорт': 30,
          'Кафе': 20,
        }.entries) {
          expect(
            find.descendant(
              of: find.widgetWithText(Row, pair.key),
              matching: find.text('${pair.value}$_nbsp%'),
            ),
            findsOneWidget,
            reason: pair.key,
          );
          final button = find.ancestor(
            of: find.text(pair.key),
            matching: find.byType(InkWell),
          );
          expect(
            tester.getSize(button).height,
            greaterThanOrEqualTo(28),
            reason: pair.key,
          );
        }
        expect(
          find.descendant(of: _legend, matching: find.textContaining('₽')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('длинное название обрезается, процент цел, переполнения нет', (
      tester,
    ) async {
      await _pump(
        tester,
        transactions: Stream.value([_expense('a', 100)]),
        categories: Stream.value([
          _category('a', 'Очень длинное название категории и ещё'),
        ]),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final row = find.descendant(of: _legend, matching: find.byType(Row));
      final card = tester.getRect(find.byType(MonthChartCard));
      expect(tester.getRect(row).right, lessThanOrEqualTo(card.right));
      expect(find.text('100$_nbsp%'), findsOneWidget);
    });

    testWidgets('шрифт 200 %: легенда под кольцом, без переполнения', (
      tester,
    ) async {
      await _pump(
        tester,
        transactions: Stream.value([_expense('a', 100)]),
        textScale: 2,
        cardHeight: 1200,
      );
      await tester.pump();

      final ring = tester.getRect(find.byType(DonutChart));
      final legend = tester.getRect(find.text('Без категории'));
      expect(legend.top, greaterThanOrEqualTo(ring.bottom));
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('«Главная» при шрифте 200 % на 360x640: нет переполнения, '
      'середина прокручивается, кнопки видны', (tester) async {
    await pumpHome(tester, const Size(360, 640), scale: 2);

    expect(tester.takeException(), isNull);
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    // Карточка кольца ниже экрана: прокручиваем до конца.
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();
    expect(find.byType(DonutChart), findsOneWidget);
    expect(
      tester.getRect(find.byType(DonutChart)).width,
      greaterThanOrEqualTo(160),
    );
    expect(tester.takeException(), isNull);
    for (final label in ['Доход', 'Расход']) {
      final rect = tester.getRect(find.text(label));
      expect(rect.bottom, lessThanOrEqualTo(640), reason: label);
      expect(rect.top, greaterThanOrEqualTo(0), reason: label);
    }
  });

  group('переход к категории', () {
    // Продукты 60 %, Транспорт 30 %, Кафе 7 %, «Остальное» (две мелкие) 3 %.
    final transactions = [
      _expense('a', 60000),
      _expense('b', 30000),
      _expense('c', 7000),
      _expense('x', 1500),
      _expense('y', 1500),
    ];
    final categories = [
      _category('a', 'Продукты'),
      _category('b', 'Транспорт'),
      _category('c', 'Кафе'),
    ];

    /// Точка кольца на [turn] оборота по часовой стрелке от «12 часов».
    Offset ringPoint(WidgetTester tester, double turn) {
      final rect = tester.getRect(find.byType(DonutChart));
      final radius = rect.width / 2 - 2 - rect.width * 0.08;
      final angle = turn * 2 * math.pi;
      return rect.center +
          Offset(radius * math.sin(angle), -radius * math.cos(angle));
    }

    Future<List<Set<String>>> pumpCard(
      WidgetTester tester, {
      List<Transaction>? data,
      List<Category>? cats,
    }) async {
      final opened = <Set<String>>[];
      await _pump(
        tester,
        transactions: Stream.value(data ?? transactions),
        categories: Stream.value(cats ?? categories),
        cardHeight: 900,
        onOpen: opened.add,
      );
      await tester.pump();
      return opened;
    }

    testWidgets('отпускание пальца на секторе «Продукты» зовёт колбэк', (
      tester,
    ) async {
      final opened = await pumpCard(tester);
      await tester.tapAt(ringPoint(tester, 0.3));
      await tester.pump(const Duration(milliseconds: 200));
      expect(opened, [
        {'a'},
      ]);
    });

    testWidgets('сектор «Остальное» зовёт колбэк с группой, мимо кольца нет', (
      tester,
    ) async {
      final opened = await pumpCard(tester);
      expect(find.text('Остальное'), findsOneWidget);
      await tester.tapAt(ringPoint(tester, 0.985));
      await tester.pump(const Duration(milliseconds: 200));
      expect(opened, [
        {'x', 'y'},
      ]);
      // Центр кольца ничего не зовёт.
      await tester.tapAt(tester.getCenter(find.byType(DonutChart)));
      await tester.pump(const Duration(milliseconds: 200));
      expect(opened, hasLength(1));
    });

    testWidgets('строки легенды зовут колбэк, «Остальное» с группой', (
      tester,
    ) async {
      final opened = await pumpCard(tester);
      await tester.tap(find.text('Транспорт'));
      await tester.tap(find.text('Остальное'));
      await tester.pump();
      expect(opened, [
        {'b'},
        {'x', 'y'},
      ]);
    });

    testWidgets('«Ещё N категорий» зовёт колбэк с оставшимися категориями; '
        'неизвестная категория не кнопка', (tester) async {
      final many = [for (var i = 0; i < 5; i++) _expense('c$i', 10000)];
      final opened = await pumpCard(
        tester,
        data: many,
        cats: [for (var i = 0; i < 5; i++) _category('c$i', 'Кат $i')],
      );
      await tester.tap(find.text('Ещё 2 категории'));
      await tester.pump();
      final expected = legendRestCategoryIds(
        _slices(many.map((t) => t).toList()),
      );
      expect(expected, hasLength(2));
      expect(opened, [expected]);

      final unknown = await pumpCard(tester, data: [_expense('gone', 100)]);
      await tester.tap(find.text('Без категории'));
      await tester.pump();
      expect(unknown, isEmpty);
    });

    testWidgets('для скринридера: строки категорий кнопки, остальные нет', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpCard(tester);
      bool isButton(String label) => tester
          .getSemantics(find.bySemanticsLabel(label))
          .flagsCollection
          .isButton;

      expect(isButton('Продукты, 600 рублей, 60 процентов'), isTrue);
      expect(isButton('Остальное, 30 рублей, 3 процента'), isTrue);

      final many = [for (var i = 0; i < 5; i++) _expense('c$i', 10000)];
      await pumpCard(tester, data: many);
      expect(isButton('Ещё 2 категории, 200 рублей, 40 процентов'), isTrue);
      semantics.dispose();
    });

    testWidgets('строка легенды высотой 28 dp', (tester) async {
      await _pump(
        tester,
        transactions: Stream.value(transactions),
        categories: Stream.value(categories),
        cardHeight: 1400,
        onOpen: (_) {},
      );
      await tester.pump();
      final rows = find.byType(InkWell);
      expect(rows, findsNWidgets(4));
      for (var i = 0; i < 4; i++) {
        expect(tester.getSize(rows.at(i)).height, 28);
      }
    });
    testWidgets('строки легенды не ниже 28 dp, шрифт 200 % без '
        'переполнения', (tester) async {
      final opened = <Set<String>>[];
      await _pump(
        tester,
        transactions: Stream.value(transactions),
        categories: Stream.value(categories),
        textScale: 2,
        cardHeight: 1400,
        onOpen: opened.add,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final rows = find.byType(InkWell);
      expect(rows, findsNWidgets(4));
      for (var i = 0; i < 4; i++) {
        expect(tester.getSize(rows.at(i)).height, greaterThanOrEqualTo(28));
      }
      await tester.tap(find.text('Кафе'));
      expect(opened, [
        {'c'},
      ]);
    });
  });

  group('legendRestCategoryIds', () {
    test('до четырёх секторов строки «Ещё N» нет — набор пуст', () {
      final four = [for (var i = 0; i < 4; i++) _expense('c$i', 10000)];
      expect(legendRestCategoryIds(_slices(four)), isEmpty);
      expect(legendRestCategoryIds(const []), isEmpty);
    });

    test('все секторы после первых трёх, включая группу «Остальное»', () {
      final data = [
        _expense('a', 50000),
        _expense('b', 20000),
        _expense('c', 10000),
        _expense('d', 5000),
        _expense('e', 5000),
        _expense('x', 1000),
        _expense('y', 1000),
      ];
      final slices = _slices(data);
      final shown = {for (final s in slices.take(3)) ...s.categoryIds};
      final all = {for (final s in slices) ...s.categoryIds};
      final rest = legendRestCategoryIds(slices);
      expect(shown, {'a', 'b', 'c'});
      expect(rest, all.difference(shown));
      expect(rest, containsAll(['d', 'e', 'x', 'y']));
    });
  });

  testWidgets('цвет метки первой строки — первый цвет палитры', (tester) async {
    await _pump(tester, transactions: Stream.value([_expense('a', 100)]));
    await tester.pump();

    final dot = tester.widget<Container>(
      find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration! as BoxDecoration).shape == BoxShape.circle,
      ),
    );
    expect(
      (dot.decoration! as BoxDecoration).color,
      AppColors.light.chartPalette.first,
    );
  });

  group('строка «Баланс»', () {
    Money rub(int minor) => Money.fromMinor(minor, 'RUB');
    final base = [_income(1200000), _expense('food', 100)];

    Future<void> pumpWith(
      WidgetTester tester,
      Stream<Money?>? balance, {
      double textScale = 1,
      double width = 360,
      double ringSize = 280,
    }) async {
      await _pump(
        tester,
        transactions: Stream.value(base),
        balanceLine: balance,
        textScale: textScale,
        width: width,
        ringSize: ringSize,
      );
      await tester.pump();
    }

    testWidgets('плюс: под «Всего» строка со знаком, цвет нейтральный', (
      tester,
    ) async {
      await pumpWith(tester, Stream.value(rub(4530000)));

      final text = 'Баланс: +${_money(4530000)}';
      expect(_inRing(text), findsOneWidget);
      final total = tester.getRect(_inRing('Всего'));
      final line = tester.getRect(_inRing(text));
      expect(line.top, greaterThan(total.bottom - 1));
      final style = tester.widget<Text>(_inRing(text)).style!;
      expect(
        style.color,
        Theme.of(tester.element(find.byType(DonutChart)))
            .colorScheme
            .onSurfaceVariant,
      );
      expect(
        style.fontSize,
        lessThan(
          tester.widget<Text>(_inRing('+${_money(1199900)}')).style!.fontSize!,
        ),
      );
    });

    testWidgets('минус: знак, цвет нейтральный', (tester) async {
      await pumpWith(tester, Stream.value(rub(-250000)));

      final text = 'Баланс: ${_money(-250000)}';
      expect(_inRing(text), findsOneWidget);
      expect(
        tester.widget<Text>(_inRing(text)).style!.color,
        Theme.of(tester.element(find.byType(DonutChart)))
            .colorScheme
            .onSurfaceVariant,
      );
    });

    testWidgets('ноль: без знака, цвет нейтральный', (tester) async {
      await pumpWith(tester, Stream.value(rub(0)));

      final text = 'Баланс: ${_money(0)}';
      expect(_inRing(text), findsOneWidget);
      expect(
        tester.widget<Text>(_inRing(text)).style!.color,
        Theme.of(tester.element(find.byType(DonutChart)))
            .colorScheme
            .onSurfaceVariant,
      );
    });

    testWidgets(
      'нет потока, null, ожидание и ошибка: строки нет, кольцо цело',
      (tester) async {
        final pending = StreamController<Money?>();
        addTearDown(pending.close);
        final cases = <Stream<Money?>?>[
          null,
          Stream.value(null),
          pending.stream,
          Stream<Money?>.error(StateError('boom')),
        ];
        for (final stream in cases) {
          await pumpWith(tester, stream);
          expect(find.textContaining('Баланс'), findsNothing);
          expect(_inRing('Всего'), findsOneWidget);
          expect(find.byType(DonutChart), findsOneWidget);
        }
      },
    );

    testWidgets('озвучка кольца: с «Баланс» и без него', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpWith(tester, Stream.value(rub(4530000)));
      expect(
        find.bySemanticsLabel(
          'Диаграмма расходов за сентябрь. '
          'Всего: плюс ${spokenMoney(rub(1199900))}. '
          'Баланс: плюс ${spokenMoney(rub(4530000))}',
        ),
        findsOneWidget,
      );

      await pumpWith(tester, Stream.value(rub(-100)));
      expect(
        find.bySemanticsLabel(
          'Диаграмма расходов за сентябрь. '
          'Всего: плюс ${spokenMoney(rub(1199900))}. '
          'Баланс: ${spokenMoney(rub(-100))}',
        ),
        findsOneWidget,
      );

      await pumpWith(tester, Stream.value(null));
      expect(
        find.bySemanticsLabel(
          'Диаграмма расходов за сентябрь. '
          'Всего: плюс ${spokenMoney(rub(1199900))}',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    for (final (width, scale, ring) in [
      (360.0, 2.0, 160.0),
      (360.0, 1.0, 280.0),
      (320.0, 2.0, 160.0),
    ]) {
      testWidgets('ширина $width, шрифт $scale: без переполнения, строка '
          'внутри дырки кольца', (tester) async {
        await pumpWith(
          tester,
          Stream.value(rub(123456789012)),
          textScale: scale,
          width: width,
          ringSize: ring,
        );

        expect(tester.takeException(), isNull);
        final line = find.textContaining('Баланс: +');
        expect(line, findsOneWidget);
        final box = tester.getRect(find.byType(DonutChart));
        final rect = tester.getRect(line);
        expect(box.contains(rect.topLeft), isTrue);
        expect(box.contains(rect.bottomRight), isTrue);
        final hole = box.width * 0.66;
        expect(rect.width, lessThanOrEqualTo(hole + 0.5));
      });
    }
  });
}
