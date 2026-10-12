import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/donut_chart.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/home/presentation/home_screen.dart';
import 'package:money_app/features/home/presentation/home_welcome_card.dart';
import 'package:money_app/features/home/presentation/month_summary_card.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

final _expense = Transaction(
  id: 'e1',
  type: TransactionType.expense,
  amount: Money.fromMinor(5000, 'RUB'),
  occurredOn: DateOnly(2026, 9, 5),
  occurredAt: DateTime.utc(2026, 9, 5, 9),
  categoryId: 'food',
);

/// «Главная» с признаком [hasAny]; потоки каждый раз новые, как их создаёт
/// `lib/app` при смене признака.
Widget _home({
  required bool? hasAny,
  List<Transaction> transactions = const [],
  double textScale = 1,
}) => MaterialApp(
  theme: AppTheme.light(),
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(
    body: HomeScreen(
      hasAnyTransactions: hasAny,
      monthExpenses: Stream.value(Money.fromMinor(5000, 'RUB')),
      monthIncome: Stream.value(Money.zero('RUB')),
      monthTransactions: Stream.value(transactions),
      categories: Stream.value(const []),
      month: DateOnly(2026, 9, 20),
      onOpenCategory: (_) {},
    ),
  ),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('операций нет: приветствие, ни итогов, ни кольца', (
    tester,
  ) async {
    await tester.pumpWidget(_home(hasAny: false));
    await _settle(tester);

    expect(find.text(homeWelcomeTitle), findsOneWidget);
    expect(find.text(homeWelcomeText), findsOneWidget);
    expect(find.text(homeWelcomeImportHint), findsOneWidget);
    expect(find.byType(MonthSummaryCard), findsNothing);
    expect(find.byType(DonutChart), findsNothing);
    expect(find.textContaining('0,00'), findsNothing);
  });

  testWidgets('в тексте кнопка «Расход» со знаком минус U+2212', (
    tester,
  ) async {
    expect(homeWelcomeText, contains('\u2212 Расход'));
    expect(homeWelcomeText, isNot(contains('- Расход')));
  });

  testWidgets('заголовок приветствия — заголовок для скринридера', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_home(hasAny: false));
    await _settle(tester);
    expect(
      tester.getSemantics(find.text(homeWelcomeTitle)).flagsCollection.isHeader,
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('неизвестно, есть ли операции: экран как обычно', (tester) async {
    await tester.pumpWidget(_home(hasAny: null));
    await _settle(tester);
    expect(find.text(homeWelcomeTitle), findsNothing);
    expect(find.byType(MonthSummaryCard), findsOneWidget);
  });

  testWidgets('первая операция: приветствие уходит, итоги и кольцо есть', (
    tester,
  ) async {
    await tester.pumpWidget(_home(hasAny: false));
    await _settle(tester);
    expect(find.text(homeWelcomeTitle), findsOneWidget);

    await tester.pumpWidget(_home(hasAny: true, transactions: [_expense]));
    await _settle(tester);
    expect(find.text(homeWelcomeTitle), findsNothing);
    expect(find.byType(MonthSummaryCard), findsOneWidget);
    expect(find.byType(DonutChart), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 360.0]) {
    testWidgets('$width dp, шрифт 200 %: приветствие без переполнения', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_home(hasAny: false, textScale: 2));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text(homeWelcomeTitle), findsOneWidget);
    });
  }

  group('homeEmptyMonthText', () {
    test('текущий месяц: «В октябре операций пока нет»', () {
      expect(
        homeEmptyMonthText(DateOnly(2026, 10, 3), isCurrentMonth: true),
        'В октябре операций пока нет',
      );
    });

    test('прошлый месяц с годом: «За май 2025 операций нет»', () {
      expect(
        homeEmptyMonthText(DateOnly(2025, 5, 1), isCurrentMonth: false),
        'За май 2025 операций нет',
      );
    });
  });
}
