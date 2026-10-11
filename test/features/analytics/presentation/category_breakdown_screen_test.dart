import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/category_avatar.dart';
import 'package:money_app/core/ui/donut_chart.dart';
import 'package:money_app/core/ui/operation_tile.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/domain/category_totals.dart';
import 'package:money_app/features/analytics/domain/shares.dart';
import 'package:money_app/features/analytics/presentation/category_breakdown_screen.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/fixture_transactions.dart';

final _range = monthRange(DateOnly(2026, 9, 1));
final _period = AnalyticsPeriod(PeriodKind.month, _range);
final String _nbsp = String.fromCharCode(0x00A0);
final String _minus = String.fromCharCode(0x2212);

Category _top(String id, String name, {CategoryKind? kind}) =>
    Category.topLevel(
      id: id,
      kind: kind ?? CategoryKind.expense,
      name: name,
      iconKey: 'icon',
      sortOrder: 0,
    );

Category _sub(
  Category parent,
  String id,
  String name, {
  bool archived = false,
}) {
  final sub = Category.subcategoryOf(
    id: id,
    parent: parent,
    name: name,
    iconKey: 'icon',
    sortOrder: 0,
  );
  return archived ? sub.archived(DateTime.utc(2026, 9, 20)) : sub;
}

Transaction _tx(
  String categoryId,
  String? subcategoryId,
  int minor, {
  TransactionType type = TransactionType.expense,
  int day = 5,
}) {
  return Transaction(
    id: '$categoryId-$subcategoryId-$minor-$day',
    type: type,
    amount: Money.fromMinor(minor, 'RUB'),
    occurredOn: DateOnly(2026, 9, day),
    occurredAt: DateTime.utc(2026, 9, day, 9),
    categoryId: categoryId,
    subcategoryId: subcategoryId,
  );
}

final _food = _top('cat-food', 'Продукты');

/// Категории тестового набора: «Продукты» с двумя подкатегориями.
List<Category> _fixtureCategories() => [
  _food,
  _sub(_food, 'sub-food-5', 'Пятёрочка'),
  _sub(_food, 'sub-food-veg', 'Овощи'),
];

Future<void> _pump(
  WidgetTester tester, {
  Category? category,
  Stream<List<Transaction>>? transactions,
  Stream<List<Category>>? categories,
  double textScale = 1,
  double height = 1600,
  ValueChanged<Transaction>? onOpenTransaction,
}) async {
  tester.view.physicalSize = Size(360, height);
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
      home: CategoryBreakdownScreen(
        category: category ?? _food,
        period: _period,
        today: DateOnly(2026, 10, 4),
        transactions: transactions ?? Stream.value(const []),
        categories: categories ?? Stream.value(const []),
        onOpenTransaction: onOpenTransaction,
      ),
    ),
  );
  // Два потока вложены друг в друга: данным нужно три кадра.
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
  // Кольцо достраивается (анимация построения).
  await tester.pump(const Duration(milliseconds: 800));
}

String _money(int minor) => formatMoney(Money.fromMinor(minor, 'RUB'));

String _pct(PercentShare s) =>
    s.isBelowOne ? '<1$_nbsp%' : '${s.percent}$_nbsp%';

Finder _inRing(String text) =>
    find.descendant(of: find.byType(DonutChart), matching: find.text(text));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  testWidgets('заголовок: имя категории и период', (tester) async {
    await _pump(tester);

    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Продукты')),
      findsOneWidget,
    );
    // Период стоит под тулбаром, а не в нём.
    expect(find.text('Сентябрь 2026'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Сентябрь 2026'),
      ),
      findsNothing,
    );
  });

  testWidgets('шрифт 200 % на 360 dp, длинное название: без переполнения, '
      'период виден', (tester) async {
    await _pump(
      tester,
      category: _top('long', 'Очень длинное название категории трат'),
      textScale: 2,
    );

    expect(tester.takeException(), isNull);
    final period = find.text('Сентябрь 2026');
    expect(period, findsOneWidget);
    final screen = tester.getRect(find.byType(CategoryBreakdownScreen));
    expect(tester.getRect(period).left, greaterThanOrEqualTo(0));
    expect(tester.getRect(period).right, lessThanOrEqualTo(screen.right));
    final title = tester.widget<Text>(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.textContaining('Очень длинное'),
      ),
    );
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
  });

  testWidgets('тестовый набор: строки совпадают с subcategoryTotals, '
      'проценты дают 100', (tester) async {
    final transactions = loadFixtureTransactions();
    await _pump(
      tester,
      transactions: Stream.value(transactions),
      categories: Stream.value(_fixtureCategories()),
    );

    final totals = subcategoryTotals(
      transactions,
      _range,
      categoryId: 'cat-food',
      currency: 'RUB',
    );
    expect(totals.length, 3);
    final shares = percentShares([for (final t in totals) t.amount]);
    expect(shares.fold<int>(0, (sum, s) => sum + (s.percent ?? 0)), 100);
    final names = {
      'sub-food-5': 'Пятёрочка',
      'sub-food-veg': 'Овощи',
      null: 'Без подкатегории',
    };
    for (var i = 0; i < totals.length; i++) {
      // Имя стоит и в строке подкатегории, и в строках операций.
      expect(find.text(names[totals[i].subcategoryId]!), findsWidgets);
      expect(
        find.text(
          '$_minus${formatMoney(totals[i].amount)} · ${_pct(shares[i])}',
        ),
        findsOneWidget,
      );
    }
    var sum = Money.zero('RUB');
    for (final t in totals) {
      sum += t.amount;
    }
    // Итог: в шапке со знаком расхода и в центре кольца.
    expect(find.text('$_minus${formatMoney(sum)}'), findsNWidgets(2));
    expect(find.byType(DonutChart), findsOneWidget);
    expect(_inRing('Всего'), findsOneWidget);
  });

  testWidgets('итог расхода цветом расхода, дохода - цветом дохода со знаком '
      '"+"', (tester) async {
    await _pump(
      tester,
      transactions: Stream.value([_tx('cat-food', null, 12345)]),
    );
    final colors = tester.element(find.byType(Scaffold)).appColors;
    // Итог в шапке стоит выше строки операции с той же суммой.
    final expense = tester.widget<Text>(
      find.text('$_minus${_money(12345)}').first,
    );
    expect(expense.style?.color, colors.expense);

    final salary = _top('salary', 'Зарплата', kind: CategoryKind.income);
    await _pump(
      tester,
      category: salary,
      transactions: Stream.value([
        _tx('salary', null, 5000000, type: TransactionType.income),
      ]),
    );
    final income = tester.widget<Text>(find.text('+${_money(5000000)}').first);
    expect(income.style?.color, colors.income);
  });

  Color? amountColorOf(WidgetTester tester, String text) {
    final rich = tester.widget<Text>(find.text(text));
    final span = rich.textSpan! as TextSpan;
    return (span.children!.first as TextSpan).style?.color;
  }

  testWidgets('сумма подкатегории: расход "-" красным, доход "+" зелёным', (
    tester,
  ) async {
    await _pump(
      tester,
      transactions: Stream.value([_tx('cat-food', null, 120000)]),
    );
    final colors = tester.element(find.byType(Scaffold)).appColors;
    expect(
      amountColorOf(tester, '$_minus${_money(120000)} · 100$_nbsp%'),
      colors.expense,
    );

    final salary = _top('salary', 'Зарплата', kind: CategoryKind.income);
    await _pump(
      tester,
      category: salary,
      transactions: Stream.value([
        _tx('salary', null, 5000000, type: TransactionType.income),
      ]),
    );
    expect(
      amountColorOf(tester, '+${_money(5000000)} · 100$_nbsp%'),
      colors.income,
    );
  });

  testWidgets('озвучка строки дохода со словом "доход"', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      category: _top('salary', 'Зарплата', kind: CategoryKind.income),
      transactions: Stream.value([
        _tx('salary', null, 100000, type: TransactionType.income),
      ]),
    );
    expect(
      find.bySemanticsLabel(
        'Без подкатегории, доход 1000 рублей, 100 процентов',
      ),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('длинный список прокручивается вместе с итогом', (tester) async {
    final subs = [for (var i = 0; i < 12; i++) 's$i'];
    await _pump(
      tester,
      transactions: Stream.value([
        for (var i = 0; i < subs.length; i++)
          _tx('cat-food', subs[i], 100000 - i * 1000),
      ]),
      categories: Stream.value([
        _food,
        for (final id in subs) _sub(_food, id, 'Под $id'),
      ]),
      height: 600,
    );
    final title = find.text('Всего за период');
    expect(title, findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pump();

    // Итог ушёл вверх вместе со списком.
    expect(title.hitTestable(), findsNothing);
  });

  testWidgets('категория без подкатегорий: одна строка, кольца нет', (
    tester,
  ) async {
    await _pump(
      tester,
      transactions: Stream.value([_tx('cat-food', null, 10000)]),
    );

    expect(find.text('Без подкатегории'), findsOneWidget);
    expect(find.text('$_minus${_money(10000)} · 100$_nbsp%'), findsOneWidget);
    expect(find.byType(DonutChart), findsNothing);
  });

  testWidgets('пустой период: текст, без кольца и списка', (tester) async {
    await _pump(
      tester,
      // Операции другой категории и другого месяца не считаются.
      transactions: Stream.value([
        _tx('cafe', null, 500),
        Transaction(
          id: 'old',
          type: TransactionType.expense,
          amount: Money.fromMinor(700, 'RUB'),
          occurredOn: DateOnly(2026, 8, 31),
          occurredAt: DateTime.utc(2026, 8, 31, 9),
          categoryId: 'cat-food',
        ),
      ]),
    );

    expect(
      find.text('За этот период в категории операций нет'),
      findsOneWidget,
    );
    expect(find.byType(DonutChart), findsNothing);
    expect(find.byType(CategoryAvatar), findsNothing);
    expect(find.text('Всего за период'), findsNothing);
  });

  testWidgets('архивная подкатегория показывается своим именем', (
    tester,
  ) async {
    await _pump(
      tester,
      transactions: Stream.value([
        _tx('cat-food', 'old', 3000),
        _tx('cat-food', 'new', 1000),
      ]),
      categories: Stream.value([
        _food,
        _sub(_food, 'old', 'Рынок', archived: true),
        _sub(_food, 'new', 'Магазин'),
      ]),
    );

    expect(find.text('Рынок'), findsWidgets);
    expect(find.text('Магазин'), findsWidgets);
  });

  testWidgets('ошибка потока: понятный текст', (tester) async {
    await _pump(tester, transactions: Stream.error(StateError('boom')));
    expect(find.text('Не удалось посчитать итоги категории'), findsOneWidget);
    expect(find.byType(DonutChart), findsNothing);

    await _pump(
      tester,
      transactions: Stream.value(const []),
      categories: Stream.error(StateError('boom')),
    );
    expect(find.text('Не удалось посчитать итоги категории'), findsOneWidget);
  });

  testWidgets('до первого ответа ничего не показывается', (tester) async {
    final transactions = StreamController<List<Transaction>>();
    addTearDown(transactions.close);
    await _pump(tester, transactions: transactions.stream);

    expect(find.text('За этот период в категории операций нет'), findsNothing);
    expect(find.text('Не удалось посчитать итоги категории'), findsNothing);
    expect(find.byType(DonutChart), findsNothing);
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets(
    'шрифт 200 % на 360 dp: без переполнения, список прокручивается',
    (tester) async {
      await _pump(
        tester,
        transactions: Stream.value(loadFixtureTransactions()),
        categories: Stream.value(_fixtureCategories()),
        textScale: 2,
        height: 640,
      );
      expect(tester.takeException(), isNull);

      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pump();
      expect(tester.takeException(), isNull);
      // Низ списка достигнут: на экране строки операций.
      expect(find.byType(OperationTile), findsWidgets);
    },
  );

  testWidgets('больше 8 строк: девятая и далее серым цветом "Остальное"', (
    tester,
  ) async {
    final subs = [for (var i = 0; i < 10; i++) 's$i'];
    await _pump(
      tester,
      transactions: Stream.value([
        for (var i = 0; i < subs.length; i++)
          _tx('cat-food', subs[i], 100000 - i * 1000),
      ]),
      categories: Stream.value([
        _food,
        for (final id in subs) _sub(_food, id, 'Под $id'),
      ]),
      height: 3000,
    );

    final colors = tester.element(find.byType(Scaffold)).appColors;
    final dots = tester
        .widgetList<CategoryAvatar>(find.byType(CategoryAvatar))
        .map((d) => d.color)
        .take(10) // сначала 10 строк подкатегорий, дальше аватары операций
        .toList();
    expect(dots.length, 10);
    expect(dots.sublist(0, 8), colors.chartPalette);
    expect(dots[8], colors.chartOther);
    expect(dots[9], colors.chartOther);
  });

  testWidgets('подсветка сектора: центр показывает название, сумму и '
      'процент', (tester) async {
    await _pump(
      tester,
      transactions: Stream.value([
        _tx('cat-food', 'a', 7500),
        _tx('cat-food', 'b', 2500),
      ]),
      categories: Stream.value([
        _food,
        _sub(_food, 'a', 'Первая'),
        _sub(_food, 'b', 'Вторая'),
      ]),
    );
    expect(_inRing('Всего'), findsOneWidget);

    // Точка на кольце сразу правее «12 часов»: там начинается первый сектор.
    final rect = tester.getRect(find.byType(DonutChart));
    final radius = rect.width / 2 - 2 - rect.width * 0.08;
    final gesture = await tester.startGesture(
      Offset(rect.center.dx + 3, rect.center.dy - radius),
    );
    await tester.pump(const Duration(milliseconds: 200));

    expect(_inRing('Первая'), findsOneWidget);
    expect(_inRing(_money(7500)), findsOneWidget);
    expect(_inRing('75$_nbsp%'), findsOneWidget);
    expect(_inRing('Всего'), findsNothing);

    await gesture.up();
    await tester.pump();
    expect(_inRing('Всего'), findsOneWidget);
  });

  group('скринридер', () {
    testWidgets('строка читается целиком, метка цвета молчит', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        transactions: Stream.value([
          _tx('cat-food', 'a', 534213),
          _tx('cat-food', 'b', 768000),
        ]),
        categories: Stream.value([
          _food,
          _sub(_food, 'a', 'Пятёрочка'),
          _sub(_food, 'b', 'Рынок'),
        ]),
      );

      // 534213 из 1302213 копеек: 41,02 %.
      expect(
        find.bySemanticsLabel(
          'Пятёрочка, расход 5342 рубля 13 копеек, 41 процент',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Рынок, расход 7680 рублей, 59 процентов'),
        findsOneWidget,
      );
      // Аватар не даёт отдельных узлов: в семантику ушли бы лишние
      // пустые элементы.
      // Две строки подкатегорий и две строки операций.
      expect(find.byType(CategoryAvatar), findsNWidgets(4));
      semantics.dispose();
    });

    testWidgets('кольцо читается одной подписью с итогом', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(
        tester,
        transactions: Stream.value([
          _tx('cat-food', 'a', 1000000),
          _tx('cat-food', 'b', 234500),
        ]),
        categories: Stream.value([
          _food,
          _sub(_food, 'a', 'А'),
          _sub(_food, 'b', 'Б'),
        ]),
      );

      expect(
        find.bySemanticsLabel(
          'Диаграмма по подкатегориям. Всего: '
          '${spokenMoney(Money.fromMinor(1234500, 'RUB'))}',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(
          'Диаграмма по подкатегориям. Всего: 12345 рублей',
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('операции категории', () {
    Finder tile(Transaction t) =>
        find.byKey(ValueKey('category-operation-${t.id}'));

    testWidgets('только этой категории и периода, новые сверху', (
      tester,
    ) async {
      final older = _tx('cat-food', null, 10100, day: 3);
      final sub = _tx('cat-food', 'sub-food-5', 20200, day: 8);
      final newest = _tx('cat-food', null, 30300, day: 20);
      final other = _tx('cat-other', null, 40400, day: 9);
      final outside = Transaction(
        id: 'outside',
        type: TransactionType.expense,
        amount: Money.fromMinor(50500, 'RUB'),
        occurredOn: DateOnly(2026, 8, 30),
        occurredAt: DateTime.utc(2026, 8, 30, 9),
        categoryId: 'cat-food',
      );
      await _pump(
        tester,
        transactions: Stream.value([older, other, sub, outside, newest]),
        categories: Stream.value(_fixtureCategories()),
      );

      expect(find.text('Операции'), findsOneWidget);
      expect(tile(other), findsNothing);
      expect(tile(outside), findsNothing);
      final ys = [
        for (final t in [newest, sub, older]) tester.getTopLeft(tile(t)).dy,
      ];
      expect(ys[0], lessThan(ys[1]));
      expect(ys[1], lessThan(ys[2]));
      // У операции с подкатегорией первая строка - её имя.
      expect(
        find.descendant(of: tile(sub), matching: find.text('Пятёрочка')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile(newest), matching: find.text('Продукты')),
        findsOneWidget,
      );
    });

    testWidgets('касание строки зовёт колбэк с операцией', (tester) async {
      final t = _tx('cat-food', null, 10100);
      Transaction? opened;
      await _pump(
        tester,
        transactions: Stream.value([t]),
        categories: Stream.value(_fixtureCategories()),
        onOpenTransaction: (value) => opened = value,
      );

      await tester.tap(tile(t));
      expect(opened, t);
    });

    testWidgets('после удаления операции строка исчезает', (tester) async {
      final a = _tx('cat-food', null, 10100, day: 3);
      final b = _tx('cat-food', null, 20200, day: 4);
      final controller = StreamController<List<Transaction>>();
      addTearDown(controller.close);
      await _pump(
        tester,
        transactions: controller.stream,
        categories: Stream.value(_fixtureCategories()),
      );
      controller.add([a, b]);
      for (var i = 0; i < 3; i++) {
        await tester.pump();
      }
      expect(tile(a), findsOneWidget);
      expect(tile(b), findsOneWidget);

      controller.add([b]);
      await tester.pump();
      expect(tile(a), findsNothing);
      expect(tile(b), findsOneWidget);
    });

    testWidgets('пустой период: заголовка «Операции» нет', (tester) async {
      await _pump(
        tester,
        transactions: Stream.value(const []),
        categories: Stream.value(_fixtureCategories()),
      );

      expect(find.text('Операции'), findsNothing);
    });
  });
}
