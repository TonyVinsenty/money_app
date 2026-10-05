import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/analytics/domain/category_totals.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/history_view.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/history/history_screen.dart';

final _today = DateOnly(2026, 9, 30);
final String _minus = String.fromCharCode(0x2212);

final _categories = [
  Category.topLevel(
    id: 'food',
    kind: CategoryKind.expense,
    name: 'Продукты',
    iconKey: 'shopping_cart',
    sortOrder: 0,
  ),
  Category.topLevel(
    id: 'salary',
    kind: CategoryKind.income,
    name: 'Зарплата',
    iconKey: 'shopping_cart',
    sortOrder: 0,
  ),
];

Transaction _tx(String id, TransactionType type, String cat, int minor) =>
    Transaction(
      id: id,
      type: type,
      amount: Money.fromMinor(minor, 'RUB'),
      occurredOn: DateOnly(2026, 9, 12),
      occurredAt: DateTime.utc(2026, 9, 12, 12),
      categoryId: cat,
    );

final _list = [
  _tx('a', TransactionType.expense, 'food', 1000050),
  _tx('b', TransactionType.expense, 'food', 842000),
  _tx('c', TransactionType.income, 'salary', 500000),
];

Money _m(int minor) => Money.fromMinor(minor, 'RUB');

Future<void> _pump(
  WidgetTester tester,
  HistoryFilter filter, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(360, 800);
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
        body: HistoryScreen(
          transactions: Stream.value(_list),
          categories: Stream.value(_categories),
          today: _today,
          month: _today,
          hasAnyTransactions: true,
          onTransactionTap: (_) {},
          filter: filter,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _rich(String plain) => find.byWidgetPredicate(
  (w) => w is RichText && w.text.toPlainText() == plain,
);

/// Цвет текстового куска [part] внутри строки итога.
Color? _colorOf(WidgetTester tester, String plain, String part) {
  final rich = tester.widget<RichText>(_rich(plain));
  Color? found;
  rich.text.visitChildren((span) {
    if (span is TextSpan && span.text == part) found = span.style?.color;
    return true;
  });
  return found;
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  final colors = AppTheme.light().extension<AppColors>()!;
  final foodTotal = totalsByCategory(
    _list,
    monthRange(_today),
    type: TransactionType.expense,
    currency: 'RUB',
  ).single.amount;

  testWidgets('только расходы: сумма равна totalsByCategory, цвет расхода', (
    tester,
  ) async {
    await _pump(tester, const HistoryFilter.expenseCategories({'food'}));
    final amount = '$_minus${formatMoney(foodTotal)}';
    final plain = '2 операции \u00b7 $amount';
    expect(foodTotal, _m(1842050));
    expect(_rich(plain), findsOneWidget);
    expect(_colorOf(tester, plain, amount), colors.expense);
  });

  testWidgets('только доходы: плюс и цвет дохода', (tester) async {
    await _pump(tester, const HistoryFilter(type: HistoryTypeFilter.income));
    final amount = '+${formatMoney(_m(500000))}';
    final plain = '1 операция \u00b7 $amount';
    expect(_rich(plain), findsOneWidget);
    expect(_colorOf(tester, plain, amount), colors.income);
  });

  testWidgets('смешанные типы: обе суммы со знаками и цветами', (tester) async {
    await _pump(tester, const HistoryFilter(expenseCategoryIds: {'food'}));
    final expense = '$_minus${formatMoney(_m(1842050))}';
    final income = '+${formatMoney(_m(500000))}';
    final plain = '3 операции \u00b7 расходы $expense \u00b7 доходы $income';
    expect(_rich(plain), findsOneWidget);
    expect(_colorOf(tester, plain, expense), colors.expense);
    expect(_colorOf(tester, plain, income), colors.income);
  });

  testWidgets('без фильтра и при пустом результате строки итога нет', (
    tester,
  ) async {
    await _pump(tester, HistoryFilter.off);
    expect(_totalLine, findsNothing);

    await _pump(tester, const HistoryFilter.expenseCategories({'zzz'}));
    expect(find.text('Ничего не найдено'), findsOneWidget);
    expect(_totalLine, findsNothing);
  });

  testWidgets('озвучка суммами словами', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, const HistoryFilter.expenseCategories({'food'}));
    expect(
      find.bySemanticsLabel('2 операции, минус 18420 рублей 50 копеек'),
      findsOneWidget,
    );
    await _pump(tester, const HistoryFilter(expenseCategoryIds: {'food'}));
    expect(
      find.bySemanticsLabel(
        '3 операции, расходы минус 18420 рублей 50 копеек, '
        'доходы плюс 5000 рублей',
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  testWidgets('шрифт 200 %: без переполнения', (tester) async {
    await _pump(
      tester,
      const HistoryFilter(expenseCategoryIds: {'food'}),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    expect(
      find.textContaining('3 операции', findRichText: true),
      findsOneWidget,
    );
  });
}

/// Любая строка итога («N операций · …»).
final _totalLine = find.byWidgetPredicate(
  (w) =>
      w is RichText && RegExp(r'^\d+ операци').hasMatch(w.text.toPlainText()),
);
