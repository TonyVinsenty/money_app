import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/masked_amount.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/domain/period_summary.dart';
import 'package:money_app/features/analytics/presentation/category_breakdown_card.dart';
import 'package:money_app/features/analytics/presentation/comparison_section.dart';
import 'package:money_app/features/analytics/presentation/dynamics_section.dart';
import 'package:money_app/features/analytics/presentation/period_summary_card.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

const _cloud = ValueKey('masked-amount-cloud');
final _today = DateOnly(2026, 10, 20);

/// Хвост суммы 12 345,67: по нему видно, остались ли цифры на экране.
const _digits = '345,67';

/// Любая сумма с копейками («12 345,67»).
/// `\s` в Dart покрывает и неразрывные пробелы.
final _anyMoney = RegExp(r'\d[\d\s]*,\d\d');

Transaction _tx(String id, int minor, DateOnly day, {String cat = 'cafe'}) =>
    Transaction(
      id: id,
      type: TransactionType.expense,
      amount: Money.fromMinor(minor, 'RUB'),
      occurredOn: day,
      occurredAt: DateTime.utc(day.year, day.month, day.day, 9),
      categoryId: cat,
    );

final _categories = [
  Category.topLevel(
    id: 'cafe',
    kind: CategoryKind.expense,
    name: 'Кафе',
    iconKey: 'icon',
    sortOrder: 0,
  ),
  Category.topLevel(
    id: 'cinema',
    kind: CategoryKind.expense,
    name: 'Кино',
    iconKey: 'icon',
    sortOrder: 1,
  ),
];

Future<void> _pump(WidgetTester tester, bool hidden, Widget child) async {
  tester.view.physicalSize = const Size(360, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: AmountsVisibility(
          hidden: hidden,
          child: ListView(padding: const EdgeInsets.all(16), children: [child]),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 800));
}

/// Весь видимый текст экрана одной строкой.
String _allText(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.byType(Text)))
    t.data ?? t.textSpan?.toPlainText() ?? '',
].join('|');

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  final summary = PeriodSummary(
    income: Money.fromMinor(2000000, 'RUB'),
    expense: Money.fromMinor(1234567, 'RUB'),
    incomeCount: 2,
    expenseCount: 5,
  );

  group('PeriodSummaryCard', () {
    testWidgets('видно: цифры на месте', (tester) async {
      await _pump(tester, false, PeriodSummaryCard(summary: summary));
      expect(_allText(tester), contains(_digits));
      expect(find.byKey(_cloud), findsNothing);
    });

    testWidgets('скрыто: цифр нет, три облачка, число операций видно', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, true, PeriodSummaryCard(summary: summary));
      expect(_allText(tester), isNot(contains(_digits)));
      expect(find.byKey(_cloud), findsNWidgets(3));
      expect(find.text('Операций: 7'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Расходы, $hiddenAmountLabel'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  testWidgets('кольцо по категориям: суммы скрыты, проценты на месте', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      true,
      CategoryBreakdownCard(
        transactions: [
          _tx('a', 1234567, DateOnly(2026, 10, 3)),
          _tx('b', 1234567, DateOnly(2026, 10, 4), cat: 'cinema'),
        ],
        range: monthRange(_today),
        categories: _categories,
      ),
    );
    expect(_allText(tester), isNot(contains(_digits)));
    expect(find.byKey(_cloud), findsWidgets);
    expect(_allText(tester), contains('50'));
    expect(
      find.bySemanticsLabel(RegExp('Кафе, $hiddenAmountLabel, ')),
      findsOneWidget,
    );
    handle.dispose();
  });

  group('DynamicsSection', () {
    Widget section() => DynamicsSection(
      transactions: [
        _tx('a', 1234567, DateOnly(2026, 10, 3)),
        _tx('b', 300000, DateOnly(2026, 10, 12)),
      ],
      period: currentPeriod(PeriodKind.month, _today),
      today: _today,
      type: TransactionType.expense,
    );

    testWidgets('видно: средняя сумма с цифрами', (tester) async {
      await _pump(tester, false, section());
      expect(_allText(tester), contains(_anyMoney));
      expect(_allText(tester), isNot(contains(maskedMoneyText)));
    });

    testWidgets('скрыто: цифр сумм нет, в тексте и на шкале точки', (
      tester,
    ) async {
      await _pump(tester, true, section());
      final text = _allText(tester);
      expect(text, contains('В среднем $maskedMoneyText'));
      expect(text, contains('Если тратить так же'));
      expect(text, isNot(contains(_anyMoney)));
    });
  });

  testWidgets('сравнение: заголовок-сумма скрыта, текст разницы тоже', (
    tester,
  ) async {
    await _pump(
      tester,
      true,
      ComparisonSection(
        transactions: [
          _tx('a', 1234567, DateOnly(2026, 10, 3)),
          _tx('b', 800000, DateOnly(2026, 9, 3)),
        ],
        range: monthRange(_today),
        previousRange: DateRange(DateOnly(2026, 9, 1), DateOnly(2026, 9, 20)),
        categories: _categories,
        today: _today,
        type: TransactionType.expense,
      ),
    );
    expect(_allText(tester), isNot(contains(_anyMoney)));
    // Облачко у итога и у суммы строки категории.
    expect(find.byKey(_cloud), findsNWidgets(2));
    expect(_allText(tester), contains(maskedMoneyText));
  });
}
