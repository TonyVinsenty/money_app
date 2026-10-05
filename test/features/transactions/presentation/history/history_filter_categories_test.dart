import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/history_view.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/history/history_screen.dart';

final _today = DateOnly(2026, 9, 30);

Category _cat(String id, String name, CategoryKind kind, int order) => Category(
  id: id,
  kind: kind,
  name: name,
  iconKey: 'shopping_cart',
  parentId: null,
  sortOrder: order,
);

final _categories = [
  _cat('food', 'Продукты', CategoryKind.expense, 0),
  _cat('cafe', 'Кафе', CategoryKind.expense, 1),
  _cat('salary', 'Зарплата', CategoryKind.income, 0),
];

Transaction _tx(String id, TransactionType type, String cat, String note) =>
    Transaction(
      id: id,
      type: type,
      amount: Money.fromMinor(10000, 'RUB'),
      occurredOn: DateOnly(2026, 9, 12),
      occurredAt: DateTime.utc(2026, 9, 12, 12),
      categoryId: cat,
      note: note,
    );

final _list = [
  _tx('a', TransactionType.expense, 'food', 'еда-раз'),
  _tx('b', TransactionType.expense, 'cafe', 'кафе-раз'),
  _tx('c', TransactionType.income, 'salary', 'зарплата-раз'),
];

class _Harness extends StatefulWidget {
  const _Harness({this.initial = HistoryFilter.off});
  final HistoryFilter initial;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late HistoryFilter filter = widget.initial;
  final transactions = Stream.value(_list).asBroadcastStream();
  final categories = Stream.value(_categories).asBroadcastStream();

  @override
  Widget build(BuildContext context) => HistoryScreen(
    transactions: transactions,
    categories: categories,
    today: _today,
    month: _today,
    hasAnyTransactions: true,
    onTransactionTap: (_) {},
    filter: filter,
    onResetFilter: () => setState(() => filter = HistoryFilter.off),
    onFilterChanged: (f) => setState(() => filter = f),
  );
}

Future<void> _open(
  WidgetTester tester, {
  HistoryFilter initial = HistoryFilter.off,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(body: _Harness(initial: initial)),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton, 'Фильтр'));
  await tester.pumpAndSettle();
}

Finder _inSheet(Finder f) =>
    find.descendant(of: find.byType(BottomSheet), matching: f);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('тип «Все»: оба раздела, тип «Расходы»: только расходы', (
    tester,
  ) async {
    await _open(tester);
    expect(find.text('Категории расходов'), findsOneWidget);
    expect(find.text('Категории доходов'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(3));

    await tester.tap(find.text('Расходы'));
    await tester.pumpAndSettle();
    expect(find.text('Категории расходов'), findsOneWidget);
    expect(find.text('Категории доходов'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
  });

  testWidgets('снять галочку: операции категории пропали из списка', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(_inSheet(find.text('Кафе')));
    await tester.pumpAndSettle();
    expect(find.textContaining('кафе-раз'), findsNothing);
    expect(find.textContaining('еда-раз'), findsOneWidget);
    expect(find.textContaining('зарплата-раз'), findsOneWidget);
    expect(find.text('Фильтр: Все · расходы: Продукты'), findsOneWidget);

    // Вернули галочку: все отмечены, набор снова null.
    await tester.tap(_inSheet(find.text('Кафе')));
    await tester.pumpAndSettle();
    expect(find.textContaining('кафе-раз'), findsOneWidget);
    expect(find.textContaining('Фильтр:'), findsNothing);
  });

  testWidgets('«Снять все»: подсказка и пустой результат; «Выбрать все»', (
    tester,
  ) async {
    await _open(tester, initial: const HistoryFilter.expenseCategories({}));
    expect(find.text('Не выбрана ни одна категория'), findsOneWidget);
    expect(find.text('Ничего не найдено'), findsOneWidget);

    await tester.tap(_inSheet(find.text('Выбрать все')));
    await tester.pumpAndSettle();
    expect(find.text('Не выбрана ни одна категория'), findsNothing);
    expect(find.text('Фильтр: Расходы'), findsOneWidget);
    expect(find.textContaining('кафе-раз'), findsOneWidget);

    await tester.tap(_inSheet(find.text('Снять все')));
    await tester.pumpAndSettle();
    expect(find.text('Не выбрана ни одна категория'), findsOneWidget);
    expect(find.text('Ничего не найдено'), findsOneWidget);
  });

  testWidgets('строки не ниже 48 dp и озвучивают отмечено/не отмечено', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _open(
      tester,
      initial: const HistoryFilter.expenseCategories({'food'}),
    );
    for (final tile in tester.widgetList(find.byType(CheckboxListTile))) {
      final size = tester.getSize(find.byWidget(tile));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    bool checked(String name) =>
        tester
            .getSemantics(_inSheet(find.text(name)).first)
            .getSemanticsData()
            .flagsCollection
            .isChecked
            .name ==
        'isTrue';
    expect(checked('Продукты'), isTrue);
    expect(checked('Кафе'), isFalse);
    handle.dispose();
  });

  testWidgets('шрифт 200 %: без переполнения, лист прокручивается', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _open(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    await tester.drag(
      _inSheet(find.byType(SingleChildScrollView)),
      const Offset(0, -400),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Готово'), findsOneWidget);
  });
}
