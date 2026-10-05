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

final _categories = <Category>[
  Category(
    id: 'food',
    kind: CategoryKind.expense,
    name: 'Продукты',
    iconKey: 'shopping_cart',
    parentId: null,
    sortOrder: 0,
  ),
  Category(
    id: 'cafe',
    kind: CategoryKind.expense,
    name: 'Кафе',
    iconKey: 'shopping_cart',
    parentId: null,
    sortOrder: 1,
  ),
];

Transaction _tx(
  String id,
  DateOnly day,
  int minor, {
  String categoryId = 'food',
  String? note,
}) => Transaction(
  id: id,
  type: TransactionType.expense,
  amount: Money.fromMinor(minor, 'RUB'),
  occurredOn: day,
  occurredAt: DateTime.utc(day.year, day.month, day.day, 12),
  categoryId: categoryId,
  note: note,
);

final _list = [
  _tx('a', DateOnly(2026, 9, 30), 10000, note: 'молоко'),
  _tx('b', DateOnly(2026, 9, 12), 90000, categoryId: 'cafe'),
  _tx('c', DateOnly(2026, 9, 5), 50000),
];

Widget _app({
  HistoryFilter filter = HistoryFilter.off,
  HistorySort sort = HistorySort.newestFirst,
  VoidCallback? onReset,
  double textScale = 1,
  List<Transaction>? list,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: HistoryScreen(
        transactions: Stream.value(list ?? _list),
        categories: Stream.value(_categories),
        today: _today,
        month: _today,
        hasAnyTransactions: true,
        onTransactionTap: (_) {},
        filter: filter,
        sort: sort,
        onResetFilter: onReset,
      ),
    ),
  );
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('фильтр выключен — полоски нет', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.textContaining('Фильтр:'), findsNothing);
    expect(find.text('Сбросить'), findsNothing);
  });

  testWidgets('фильтр включён — полоска с подписью и «Сбросить»', (
    tester,
  ) async {
    var resets = 0;
    await tester.pumpWidget(
      _app(
        filter: const HistoryFilter.expenseCategories({'food'}),
        onReset: () => resets++,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Фильтр: Расходы · Продукты'), findsOneWidget);
    expect(find.text('Кафе'), findsNothing);
    expect(find.bySemanticsLabel('Сбросить фильтр'), findsOneWidget);
    await tester.tap(find.text('Сбросить'));
    expect(resets, 1);
  });

  testWidgets('порядок: кнопка «Фильтр» выше полоски, полоска выше списка', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(filter: const HistoryFilter.expenseCategories({'food'})),
    );
    await tester.pumpAndSettle();
    final button = tester.getTopLeft(find.widgetWithText(TextButton, 'Фильтр'));
    final strip = tester.getTopLeft(find.text('Фильтр: Расходы · Продукты'));
    final row = tester.getTopLeft(find.text('молоко'));
    expect(button.dy, lessThan(strip.dy));
    expect(strip.dy, lessThan(row.dy));
  });

  testWidgets('пустой результат: свой текст и кнопка, не «операций нет»', (
    tester,
  ) async {
    var resets = 0;
    await tester.pumpWidget(
      _app(
        filter: const HistoryFilter.expenseCategories({'nobody'}),
        onReset: () => resets++,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ничего не найдено'), findsOneWidget);
    expect(
      find.text('За сентябрь 2026 нет операций, подходящих под фильтр'),
      findsOneWidget,
    );
    expect(find.textContaining('операций нет'), findsNothing);
    await tester.tap(find.text('Сбросить фильтр'));
    expect(resets, 1);
  });

  testWidgets('по сумме: без заголовков дней, день в строке и в озвучке', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(sort: HistorySort.largestFirst));
    await tester.pumpAndSettle();
    expect(find.text('Сегодня · молоко'), findsOneWidget);
    expect(find.text('12 сентября'), findsOneWidget);
    expect(find.text('5 сентября'), findsOneWidget);
    expect(find.textContaining('суббота'), findsNothing);
    expect(find.bySemanticsLabel(RegExp(r'Кафе, 12 сентября')), findsOneWidget);
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(y('12 сентября'), lessThan(y('5 сентября')));
    expect(y('5 сентября'), lessThan(y('Сегодня · молоко')));
    handle.dispose();
  });

  testWidgets('«Сначала старые»: заголовки дней по возрастанию', (
    tester,
  ) async {
    await tester.pumpWidget(_app(sort: HistorySort.oldestFirst));
    await tester.pumpAndSettle();
    double y(String t) => tester.getTopLeft(find.text(t)).dy;
    final five = y('суббота, 5 сентября');
    final twelve = y('суббота, 12 сентября');
    expect(five, lessThan(twelve));
    expect(twelve, lessThan(y('Сегодня')));
  });

  testWidgets('шрифт 200%: полоска переносится, «Сбросить» не ниже 48 dp', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        textScale: 2,
        filter: const HistoryFilter.expenseCategories({'food', 'cafe'}),
        onReset: () {},
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final size = tester.getSize(find.widgetWithText(TextButton, 'Сбросить'));
    expect(size.height, greaterThanOrEqualTo(48));
    expect(size.width, greaterThanOrEqualTo(48));
  });
}
