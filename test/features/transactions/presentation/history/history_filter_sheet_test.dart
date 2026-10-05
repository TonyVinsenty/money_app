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
import 'package:money_app/features/transactions/presentation/history/history_filter_label.dart';
import 'package:money_app/features/transactions/presentation/history/history_screen.dart';

final _today = DateOnly(2026, 9, 30);

final _categories = <Category>[
  Category(
    id: 'food',
    kind: CategoryKind.expense,
    name: 'Продукты',
    iconKey: 'shopping_cart',
    parentId: null,
    sortOrder: 0,
  ),
];

Transaction _tx(String id, TransactionType type, String note) => Transaction(
  id: id,
  type: type,
  amount: Money.fromMinor(10000, 'RUB'),
  occurredOn: DateOnly(2026, 9, 12),
  occurredAt: DateTime.utc(2026, 9, 12, 12),
  categoryId: 'food',
  note: note,
);

final _list = [
  _tx('a', TransactionType.expense, 'расход-один'),
  _tx('b', TransactionType.income, 'доход-один'),
];

/// Держит фильтр в состоянии, как это делает контроллер приложения.
class _Harness extends StatefulWidget {
  const _Harness({
    required this.transactions,
    this.initial = HistoryFilter.off,
    this.hasAny = true,
    super.key,
  });

  final Stream<List<Transaction>> transactions;
  final HistoryFilter initial;
  final bool hasAny;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late HistoryFilter filter = widget.initial;
  final categories = Stream.value(_categories).asBroadcastStream();

  @override
  Widget build(BuildContext context) => HistoryScreen(
    transactions: widget.transactions,
    categories: categories,
    today: _today,
    month: _today,
    hasAnyTransactions: widget.hasAny,
    onTransactionTap: (_) {},
    filter: filter,
    sort: HistorySort.largestFirst,
    onResetFilter: () => setState(() => filter = HistoryFilter.off),
    onFilterChanged: (f) => setState(() => filter = f),
  );
}

Widget _app(Widget body, {double textScale = 1}) => MaterialApp(
  theme: AppTheme.light(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(body: body),
);

Future<void> _pump(
  WidgetTester tester, {
  HistoryFilter initial = HistoryFilter.off,
  List<Transaction>? list,
  bool hasAny = true,
  double textScale = 1,
  Stream<List<Transaction>>? stream,
}) async {
  await tester.pumpWidget(
    _app(
      _Harness(
        key: UniqueKey(),
        transactions: stream ?? Stream.value(list ?? _list),
        initial: initial,
        hasAny: hasAny,
      ),
      textScale: textScale,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Фильтр'));
  await tester.pumpAndSettle();
}

const _income = HistoryFilter(type: HistoryTypeFilter.income);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('historyFilterSpoken', () {
    test('выключен — просто «Фильтр»', () {
      expect(historyFilterSpoken(HistoryFilter.off, _categories), 'Фильтр');
    });

    test('тип и категория — через запятую, с маленькой буквы', () {
      expect(
        historyFilterSpoken(
          const HistoryFilter.expenseCategories({'food'}),
          _categories,
        ),
        'Фильтр, включён: расходы, Продукты',
      );
      expect(
        historyFilterSpoken(_income, _categories),
        'Фильтр, включён: доходы',
      );
    });
  });

  testWidgets('кнопка «Фильтр» озвучивается в обоих состояниях', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester);
    expect(find.bySemanticsLabel('Фильтр'), findsOneWidget);
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isFalse);

    await _pump(
      tester,
      initial: const HistoryFilter.expenseCategories({'food'}),
    );
    expect(
      find.bySemanticsLabel('Фильтр, включён: расходы, Продукты'),
      findsOneWidget,
    );
    expect(tester.widget<Badge>(find.byType(Badge)).isLabelVisible, isTrue);
    handle.dispose();
  });

  testWidgets('лист: «Готово» закрывает', (tester) async {
    await _pump(tester);
    await _openSheet(tester);
    expect(find.text('Готово'), findsOneWidget);
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(find.text('Готово'), findsNothing);
  });

  testWidgets('лист: системная «Назад» закрывает', (tester) async {
    await _pump(tester);
    await _openSheet(tester);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Готово'), findsNothing);
  });

  testWidgets('лист: смахивание вниз закрывает', (tester) async {
    await _pump(tester);
    await _openSheet(tester);
    await tester.drag(find.text('Готово'), const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(find.text('Готово'), findsNothing);
  });

  testWidgets('смена типа сразу меняет список под листом', (tester) async {
    await _pump(tester);
    await _openSheet(tester);
    expect(find.textContaining('расход-один'), findsOneWidget);
    expect(find.textContaining('доход-один'), findsOneWidget);

    await tester.tap(find.text('Доходы'));
    await tester.pumpAndSettle();
    expect(find.text('Готово'), findsOneWidget);
    expect(find.text('Фильтр: Доходы'), findsOneWidget);
    expect(find.textContaining('расход-один'), findsNothing);
    expect(find.textContaining('доход-один'), findsOneWidget);
  });

  testWidgets('смена типа сохраняет наборы категорий', (tester) async {
    HistoryFilter? last;
    await tester.pumpWidget(
      _app(
        HistoryScreen(
          transactions: Stream.value(_list),
          categories: Stream.value(_categories),
          today: _today,
          month: _today,
          hasAnyTransactions: true,
          onTransactionTap: (_) {},
          filter: const HistoryFilter.expenseCategories({'food'}),
          onFilterChanged: (f) => last = f,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openSheet(tester);
    await tester.tap(find.text('Все'));
    await tester.pumpAndSettle();
    expect(last?.type, HistoryTypeFilter.all);
    expect(last?.expenseCategoryIds, {'food'});
  });

  testWidgets('«Сбросить» в листе выключает фильтр, сортировку не трогает', (
    tester,
  ) async {
    await _pump(tester, initial: _income);
    expect(find.textContaining('расход-один'), findsNothing);
    await _openSheet(tester);
    final reset = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.widgetWithText(TextButton, 'Сбросить'),
    );
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(find.textContaining('расход-один'), findsOneWidget);
    expect(find.textContaining('Фильтр:'), findsNothing);
    expect(find.text('Сначала крупные'), findsOneWidget);
    // Фильтр выключен: «Сбросить» в листе недоступна.
    expect(tester.widget<TextButton>(reset).onPressed, isNull);
  });

  testWidgets('выбранный сегмент озвучивается «выбрано»', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, initial: _income);
    await _openSheet(tester);
    String selected(String label) => tester
        .getSemantics(
          find
              .descendant(
                of: find.byType(SegmentedButton<HistoryTypeFilter>),
                matching: find.text(label),
              )
              .first,
        )
        .getSemanticsData()
        .flagsCollection
        .isSelected
        .name;
    expect(selected('Доходы'), 'isTrue');
    expect(selected('Все'), 'isFalse');
    handle.dispose();
  });

  testWidgets('«Фильтр» виден в пустом месяце и в «Ничего не найдено»', (
    tester,
  ) async {
    await _pump(tester, list: const []);
    expect(find.text('За сентябрь 2026 операций нет'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Фильтр'), findsOneWidget);
    expect(find.text('Сначала крупные'), findsNothing);

    await _pump(
      tester,
      initial: const HistoryFilter.expenseCategories({'nobody'}),
    );
    expect(find.text('Ничего не найдено'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Фильтр'), findsOneWidget);
    expect(find.text('Сначала крупные'), findsNothing);
  });

  testWidgets('в «Операций пока нет» кнопки «Фильтр» нет', (tester) async {
    await _pump(tester, list: const [], hasAny: false);
    expect(find.text('Операций пока нет'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Фильтр'), findsNothing);
  });

  testWidgets('смена фильтра не подписывается на поток заново', (tester) async {
    var listens = 0;
    final stream = Stream.value(_list)
        .asBroadcastStream(onListen: (_) => listens++);
    await _pump(tester, stream: stream);
    final before = listens;
    await _openSheet(tester);
    await tester.tap(find.text('Расходы'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(listens, before);
  });

  testWidgets('шрифт 200%: лист прокручивается, без переполнения', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await _pump(tester, textScale: 2);
    await _openSheet(tester);
    expect(tester.takeException(), isNull);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    await tester.drag(find.text('Готово'), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Готово'), findsOneWidget);
  });
}
