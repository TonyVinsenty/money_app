import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/analytics/presentation/operations_section.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

final _today = DateOnly(2026, 10, 12);
final _range = monthRange(DateOnly(2026, 10, 1));

final _food = Category.topLevel(
  id: 'food',
  kind: CategoryKind.expense,
  name: 'Продукты',
  iconKey: 'icon',
  sortOrder: 0,
);
final _milk = Category.subcategoryOf(
  id: 'milk',
  parent: _food,
  name: 'Молочка',
  iconKey: 'icon',
  sortOrder: 0,
);

Transaction _tx(
  String id,
  int minor, {
  TransactionType type = TransactionType.expense,
  DateOnly? day,
  String? note,
  String category = 'food',
  String? subcategory,
}) {
  final on = day ?? DateOnly(2026, 10, 3);
  return Transaction(
    id: id,
    type: type,
    amount: Money.fromMinor(minor, 'RUB'),
    occurredOn: on,
    occurredAt: DateTime.utc(on.year, on.month, on.day, 9),
    categoryId: category,
    subcategoryId: subcategory,
    note: note,
  );
}

Future<void> _pump(
  WidgetTester tester,
  List<Transaction> transactions, {
  TransactionType type = TransactionType.expense,
  ValueChanged<Transaction>? onOpen,
  double textScale = 1,
  double width = 360,
}) async {
  tester.view.physicalSize = Size(width, 800);
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
        body: SingleChildScrollView(
          child: OperationsSection(
            transactions: transactions,
            range: _range,
            categories: [_food, _milk],
            today: _today,
            type: type,
            onOpenTransaction: onOpen,
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('двенадцать операций: десять строк по убыванию суммы', (
    tester,
  ) async {
    await _pump(tester, [for (var i = 1; i <= 12; i++) _tx('t$i', i * 1000)]);

    expect(find.text('Крупные расходы'), findsOneWidget);
    final list = find.byKey(OperationsSection.listKey);
    final rows = find.descendant(
      of: list,
      matching: find.byType(InkWell),
      skipOffstage: false,
    );
    expect(rows, findsNothing, reason: 'без колбэка строки не кнопки');
    // Строки t12..t3 есть, t2 и t1 нет; порядок сверху вниз по убыванию.
    for (var i = 3; i <= 12; i++) {
      expect(find.byKey(OperationsSection.rowKey('t$i')), findsOneWidget);
    }
    expect(find.byKey(OperationsSection.rowKey('t2')), findsNothing);
    final ys = [
      for (var i = 12; i >= 3; i--)
        tester.getTopLeft(find.byKey(OperationsSection.rowKey('t$i'))).dy,
    ];
    expect(ys, [...ys]..sort());
  });

  testWidgets('меньше десяти: столько строк, сколько операций; строка как в '
      '«Истории»', (tester) async {
    await _pump(tester, [
      _tx(
        'a',
        540000,
        note: 'ремонт',
        day: DateOnly(2026, 10, 12),
        subcategory: 'milk',
      ),
      _tx('b', 100000, day: DateOnly(2026, 10, 2)),
    ]);

    expect(find.byKey(OperationsSection.rowKey('a')), findsOneWidget);
    expect(find.byKey(OperationsSection.rowKey('b')), findsOneWidget);
    expect(find.text('Продукты · Молочка'), findsOneWidget);
    expect(find.text('Сегодня · ремонт'), findsOneWidget);
    expect(find.text('2 октября'), findsOneWidget);
    expect(find.textContaining('5 400,00'), findsOneWidget);
  });

  testWidgets('чужой период и другой тип не попадают', (tester) async {
    await _pump(tester, [
      _tx('now', 5000),
      _tx('old', 90000, day: DateOnly(2026, 9, 30)),
      _tx('inc', 70000, type: TransactionType.income),
    ]);

    expect(find.byKey(OperationsSection.rowKey('now')), findsOneWidget);
    expect(find.byKey(OperationsSection.rowKey('old')), findsNothing);
    expect(find.byKey(OperationsSection.rowKey('inc')), findsNothing);
  });

  testWidgets('доходы: свой заголовок и плюс у суммы', (tester) async {
    await _pump(tester, [
      _tx('inc', 70000, type: TransactionType.income),
    ], type: TransactionType.income);

    expect(find.text('Крупные доходы'), findsOneWidget);
    expect(find.textContaining('+700,00'), findsOneWidget);
  });

  testWidgets('пустой тип: текст как в других разделах', (tester) async {
    await _pump(tester, [_tx('inc', 70000, type: TransactionType.income)]);

    expect(find.text('За этот период расходов нет'), findsOneWidget);
    expect(find.byKey(OperationsSection.listKey), findsNothing);
  });

  testWidgets('касание зовёт колбэк с операцией', (tester) async {
    final opened = <String>[];
    await _pump(tester, [_tx('a', 1000)], onOpen: (t) => opened.add(t.id));

    await tester.tap(find.byKey(OperationsSection.rowKey('a')));
    expect(opened, ['a']);
  });

  testWidgets('озвучка строки: один узел', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, [_tx('a', 100000, note: 'хлеб')], onOpen: (_) {});

    final label = tester
        .getSemantics(find.byKey(OperationsSection.rowKey('a')))
        .label;
    expect(label, startsWith('Расход '));
    expect(label, contains('Продукты'));
    expect(label, contains('3 октября'));
    expect(label, contains('комментарий: хлеб'));
    handle.dispose();
  });

  testWidgets('360 dp и шрифт 200 %: без переполнения', (tester) async {
    await _pump(tester, [
      _tx(
        'a',
        123456789,
        note: 'очень длинный комментарий к крупной покупке',
        subcategory: 'milk',
      ),
      for (var i = 0; i < 9; i++) _tx('t$i', 1000 + i),
    ], textScale: 2);

    expect(tester.takeException(), isNull);
    expect(find.byKey(OperationsSection.rowKey('a')), findsOneWidget);
  });
}
