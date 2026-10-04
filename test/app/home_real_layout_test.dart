import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app_shell.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/donut_chart.dart';
import 'package:money_app/core/ui/font_scale.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/home/presentation/home_action_bar.dart';
import 'package:money_app/features/home/presentation/home_screen.dart';
import 'package:money_app/features/home/presentation/month_summary_card.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

/// «Главная» в настоящем каркасе (с NavigationBar и HomeActionBar), с отступами
/// системных панелей: строка состояния сверху и жестовая навигация снизу.

/// Масштаб как в Android 14+: мелкий текст растёт сильнее крупного. 14 sp при
/// «200 %» дают 28, а всё, что крупнее 20 sp, растёт лишь в 1,1 раза.
class _NonLinearScaler extends TextScaler {
  const _NonLinearScaler();

  @override
  double scale(double fontSize) =>
      fontSize <= 20 ? fontSize * 2 : 40 + (fontSize - 20) * 1.1;

  @override
  // ignore: deprecated_member_use
  double get textScaleFactor => 2;
}

Category _category(String id, String name) => Category.topLevel(
  id: id,
  kind: CategoryKind.expense,
  name: name,
  iconKey: 'icon',
  sortOrder: 0,
);

Transaction _expense(String categoryId, int minor) => Transaction(
  id: '$categoryId-$minor',
  type: TransactionType.expense,
  amount: Money.fromMinor(minor, 'RUB'),
  occurredOn: DateOnly(2026, 9, 5),
  occurredAt: DateTime.utc(2026, 9, 5, 9),
  categoryId: categoryId,
);

Future<void> _pumpShell(
  WidgetTester tester,
  Size size,
  TextScaler scaler,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
  tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
  addTearDown(tester.view.reset);
  final month = DateOnly(2026, 9, 20);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: scaler),
        child: child!,
      ),
      home: AppShell(
        tabs: [
          AppTab(
            label: 'Главная',
            icon: Icons.home_outlined,
            selectedIcon: Icons.home,
            builder: (_) => HomeScreen(
              monthExpenses: Stream.value(Money.fromMinor(12803388, 'RUB')),
              monthIncome: Stream.value(Money.fromMinor(10294900, 'RUB')),
              monthTransactions: Stream.value([
                _expense('a', 5000),
                _expense('b', 3000),
                _expense('c', 2000),
              ]),
              categories: Stream.value([
                _category('a', 'Еда'),
                _category('b', 'Дом'),
                _category('c', 'Кафе'),
              ]),
              month: month,
              onOpenCategory: (_) {},
            ),
            actionsBuilder: (_) => HomeActionBar(onAddTransaction: (_) {}),
          ),
          for (final name in ['Один', 'Два'])
            AppTab(
              label: name,
              icon: Icons.circle_outlined,
              selectedIcon: Icons.circle,
              builder: (_) => const SizedBox(),
            ),
        ],
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('393x852, 100 %, статус-бар и жестовая навигация по 24 dp: '
      'без прокрутки, кольцо крупное', (tester) async {
    await _pumpShell(tester, const Size(393, 852), TextScaler.noScaling);

    expect(tester.takeException(), isNull);
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(HomeScreen),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.maxScrollExtent, 0);
    final ring = tester.getRect(find.byType(DonutChart));
    expect(ring.width, greaterThanOrEqualTo(280));
    // Легенда кончается выше панели кнопок.
    expect(
      tester.getRect(find.byType(Wrap)).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(HomeActionBar)).top),
    );
  });

  testWidgets('нелинейный масштаб «200 %»: итоги столбиком, оценка высоты '
      'сходится с раскладкой', (tester) async {
    await _pumpShell(tester, const Size(393, 800), const _NonLinearScaler());

    expect(tester.takeException(), isNull);
    final expense = tester.getRect(find.byKey(MonthSummaryCard.expenseKey));
    final income = tester.getRect(find.byKey(MonthSummaryCard.incomeKey));
    expect(income.top, greaterThanOrEqualTo(expense.bottom));

    final context = tester.element(find.byType(MonthSummaryCard));
    final scale = fontScaleOf(context);
    expect(scale, 2);
    final estimate = estimateSummaryHeight(393 - 2 * 16 - 2 * 16, scale);
    final actual = tester.getSize(find.byType(MonthSummaryCard)).height;
    // Оценка близка к раскладке (в тестовом шрифте Ahem буквы шире настоящих,
    // поэтому допуск 40 dp в обе стороны). Старый расчёт по scale(100) принял
    // бы этот экран за «в ряд» и занизил бы высоту почти вдвое.
    expect((estimate - actual).abs(), lessThanOrEqualTo(40));
  });
}
