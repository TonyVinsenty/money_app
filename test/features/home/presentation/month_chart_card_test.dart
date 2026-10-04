import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/donut_chart.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/analytics/domain/category_totals.dart';
import 'package:money_app/features/analytics/domain/shares.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
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
  double cardHeight = 700,
  ThemeMode mode = ThemeMode.light,
}) async {
  tester.view.physicalSize = const Size(360, 1600);
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

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  testWidgets('пустой месяц: серое кольцо, баланс нейтральный, текст вместо '
      'легенды', (tester) async {
    await _pump(tester);

    expect(find.text('Расходы по категориям'), findsOneWidget);
    expect(find.text('В этом месяце расходов пока нет'), findsOneWidget);
    expect(_inRing('Баланс'), findsOneWidget);
    final colors = tester.element(find.byType(MonthChartCard)).appColors;
    // Ноль нейтральный: ни цвет расхода, ни цвет дохода.
    final balance = tester.widget<Text>(_inRing(_money(0)));
    expect(balance.style?.color, isNot(colors.expense));
    expect(balance.style?.color, isNot(colors.income));
    final empty = tester.widget<Text>(
      find.text('В этом месяце расходов пока нет'),
    );
    expect(empty.style?.color, isNot(colors.expense));
  });

  testWidgets('сентябрь тестового набора: баланс и проценты легенды', (
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

    final colors = tester.element(find.byType(MonthChartCard)).appColors;
    final balance = tester.widget<Text>(_inRing(_money(-2508488)));
    expect(balance.style?.color, colors.expense);

    // Три крупнейших категории: название, сумма и процент как в domain.
    for (final slice in slices.take(3)) {
      final id = slice.categoryIds.single;
      expect(find.text('Кат $id'), findsOneWidget);
      expect(
        find.text('${formatMoney(slice.amount)} · ${_pct(slice.share)}'),
        findsOneWidget,
      );
    }
    // Остаток свернут в «Ещё N категорий».
    final rest = slices.skip(3).toList();
    final count = rest.fold<int>(0, (sum, s) => sum + s.categoryIds.length);
    final restMoney = rest.fold(Money.zero('RUB'), (sum, s) => sum + s.amount);
    final restPercent = rest.fold<int>(0, (sum, s) => sum + s.share.percent!);
    expect(count, greaterThan(1));
    expect(find.textContaining('Ещё $count '), findsOneWidget);
    expect(
      find.text('${formatMoney(restMoney)} · $restPercent$_nbsp%'),
      findsOneWidget,
    );
  });

  testWidgets('положительный баланс: плюс и цвет дохода', (tester) async {
    await _pump(
      tester,
      transactions: Stream.value([_income(1234567), _expense('food', 100)]),
      categories: Stream.value([_category('food', 'Еда')]),
    );
    await tester.pump();

    final colors = tester.element(find.byType(MonthChartCard)).appColors;
    final text = tester.widget<Text>(_inRing('+${_money(1234467)}'));
    expect(text.style?.color, colors.income);
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

  testWidgets('подсветка сектора меняет центр, отпускание возвращает баланс', (
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
    expect(_inRing('Баланс'), findsOneWidget);

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
    expect(_inRing('Баланс'), findsNothing);

    await gesture.up();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_inRing('Баланс'), findsOneWidget);
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
    expect(find.text('Баланс'), findsNothing);
    expect(find.byType(DonutChart), findsNothing);

    controller.add([_expense('food', 1000)]);
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    expect(find.byType(DonutChart), findsOneWidget);
    expect(find.text('В этом месяце расходов пока нет'), findsNothing);
  });

  group('скринридер', () {
    testWidgets('подпись кольца: месяц и баланс со знаком', (tester) async {
      final semantics = tester.ensureSemantics();
      final data = _fixture();
      await _pump(
        tester,
        transactions: Stream.value(data.transactions),
        categories: Stream.value(data.categories),
      );
      await tester.pump();
      expect(
        find.bySemanticsLabel(
          'Диаграмма расходов за сентябрь. Баланс: минус 25084 рубля 88 копеек',
        ),
        findsOneWidget,
      );

      await _pump(
        tester,
        transactions: Stream.value([_income(1234567), _expense('food', 100)]),
      );
      await tester.pump();
      expect(
        find.bySemanticsLabel(
          'Диаграмма расходов за сентябрь. Баланс: плюс 12344 рубля 67 копеек',
        ),
        findsOneWidget,
      );

      await _pump(tester);
      await tester.pump();
      expect(
        find.bySemanticsLabel(
          'Диаграмма расходов за сентябрь. Баланс: 0 рублей',
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

  group('раскладка', () {
    testWidgets('обычный шрифт на 360 dp: легенда справа от кольца', (
      tester,
    ) async {
      await _pump(tester, transactions: Stream.value([_expense('a', 100)]));
      await tester.pump();

      final ring = tester.getRect(find.byType(DonutChart));
      final legend = tester.getRect(find.text('Без категории'));
      expect(legend.left, greaterThanOrEqualTo(ring.right));
    });

    testWidgets('шрифт 200 %: легенда под кольцом', (tester) async {
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

  testWidgets('«Главная» при шрифте 200 % на 360 dp: нет переполнения, '
      'кнопки видны', (tester) async {
    final data = _fixture();
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: HomeScreen(
            onAddTransaction: (_) {},
            monthExpenses: Stream.value(Money.fromMinor(12803388, 'RUB')),
            monthIncome: Stream.value(Money.fromMinor(10294900, 'RUB')),
            monthTransactions: Stream.value(data.transactions),
            categories: Stream.value(data.categories),
            month: _month,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(DonutChart), findsOneWidget);
    for (final label in ['Доход', 'Расход']) {
      final rect = tester.getRect(find.text(label));
      expect(rect.bottom, lessThanOrEqualTo(640), reason: label);
      expect(rect.top, greaterThanOrEqualTo(0), reason: label);
    }
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
}
