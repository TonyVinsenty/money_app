import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/masked_amount.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/home/presentation/home_screen.dart';
import 'package:money_app/features/home/presentation/month_chart_card.dart';
import 'package:money_app/features/home/presentation/month_summary_card.dart';
import 'package:money_app/features/settings/domain/home_balance_line.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

const _cloud = ValueKey('masked-amount-cloud');

final _expense = Money.fromMinor(1234550, 'RUB');
final _expenseText = '${String.fromCharCode(0x2212)}${formatMoney(_expense)}';
final _balanceText = formatMoney(Money.fromMinor(-1234550, 'RUB'));
final _lineMoney = Money.fromMinor(987600, 'RUB');

Widget _host({required bool hidden, required Widget child}) => MaterialApp(
  theme: AppTheme.light(),
  home: Scaffold(
    body: AmountsVisibility(
      hidden: hidden,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  ),
);

Widget _summary({required bool hidden}) => _host(
  hidden: hidden,
  child: IntrinsicHeight(
    child: MonthSummaryCard(
      expenses: Stream.value(_expense),
      income: Stream.value(Money.zero('RUB')),
      month: DateOnly(2026, 10, 4),
    ),
  ),
);

Widget _chart({required bool hidden}) => _host(
  hidden: hidden,
  child: SizedBox(
    height: 500,
    child: MonthChartCard(
      transactions: Stream.value([
        Transaction(
          id: 't1',
          type: TransactionType.expense,
          amount: _expense,
          occurredOn: DateOnly(2026, 10, 5),
          occurredAt: DateTime.utc(2026, 10, 5, 9),
          categoryId: 'food',
        ),
      ]),
      categories: Stream.value([
        Category.topLevel(
          id: 'food',
          kind: CategoryKind.expense,
          name: 'Еда',
          iconKey: 'icon',
          sortOrder: 0,
        ),
      ]),
      month: DateOnly(2026, 10, 4),
      ringSize: 280,
      balanceLine: Stream.value(_lineMoney),
      balanceLineKind: HomeBalanceLine.accounts,
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 800));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  group('MonthSummaryCard', () {
    testWidgets('видно: сумма на месте, облачка нет', (tester) async {
      await tester.pumpWidget(_summary(hidden: false));
      await tester.pump();
      expect(find.text(_expenseText), findsOneWidget);
      expect(find.byKey(_cloud), findsNothing);
    });

    testWidgets('скрыто: суммы нет, облачко и озвучка', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_summary(hidden: true));
      await tester.pump();
      expect(find.text(_expenseText), findsNothing);
      expect(find.byKey(_cloud), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Расходы за .*$hiddenAmountLabel')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('MonthChartCard', () {
    testWidgets('видно: баланс и строка счетов', (tester) async {
      await tester.pumpWidget(_chart(hidden: false));
      await _settle(tester);
      expect(find.text(_balanceText), findsOneWidget);
      expect(
        find.text('На счетах: ${formatMoney(_lineMoney)}'),
        findsOneWidget,
      );
      expect(find.byKey(_cloud), findsNothing);
    });

    testWidgets('скрыто: суммы скрыты, проценты остались', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_chart(hidden: true));
      await _settle(tester);
      expect(find.text(_balanceText), findsNothing);
      expect(find.textContaining(formatMoney(_lineMoney)), findsNothing);
      expect(find.text('На счетах: $maskedMoneyText'), findsOneWidget);
      expect(find.byKey(_cloud), findsOneWidget);
      expect(find.textContaining('100'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Диаграмма расходов.*$hiddenAmountLabel')),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel(RegExp('Еда, $hiddenAmountLabel, ')),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('«Глаз» в HomeScreen', () {
    Widget home({required bool hide, ValueChanged<bool>? onChanged}) =>
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: HomeScreen(
              monthExpenses: Stream.value(Money.zero('RUB')),
              monthIncome: Stream.value(Money.zero('RUB')),
              monthTransactions: Stream.value(const []),
              categories: Stream.value(const []),
              month: DateOnly(2026, 9, 20),
              onOpenCategory: (_) {},
              hideAmounts: hide,
              onHideAmountsChanged: onChanged,
            ),
          ),
        );

    testWidgets('без обработчика значка нет', (tester) async {
      await tester.pumpWidget(home(hide: false));
      await tester.pump();
      expect(find.byKey(MonthSummaryCard.hideAmountsKey), findsNothing);
    });

    testWidgets('суммы видны: «Скрыть суммы», нажатие даёт true', (
      tester,
    ) async {
      bool? got;
      await tester.pumpWidget(home(hide: false, onChanged: (v) => got = v));
      await tester.pump();
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
      expect(find.byTooltip('Скрыть суммы'), findsOneWidget);
      await tester.tap(find.byKey(MonthSummaryCard.hideAmountsKey));
      expect(got, isTrue);
    });

    testWidgets('суммы скрыты: «Показать суммы», нажатие даёт false', (
      tester,
    ) async {
      bool? got;
      await tester.pumpWidget(home(hide: true, onChanged: (v) => got = v));
      await tester.pump();
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
      expect(find.byTooltip('Показать суммы'), findsOneWidget);
      await tester.tap(find.byKey(MonthSummaryCard.hideAmountsKey));
      expect(got, isFalse);
    });
  });
}
