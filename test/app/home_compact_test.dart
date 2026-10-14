import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app_shell.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/color_dot.dart';
import 'package:money_app/core/ui/donut_chart.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/home/presentation/home_action_bar.dart';
import 'package:money_app/features/home/presentation/home_screen.dart';
import 'package:money_app/features/home/presentation/month_chart_card.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../support/roboto_font.dart';

/// Компактный режим «Главной» (D3, шаг 8.19): короткий телефон.

const _names = {
  'a': 'Дом',
  'b': 'Займы',
  'c': 'Еда',
  'd': 'Кафе',
  'e': 'Такси',
};

Transaction _expense(String categoryId, int minor) => Transaction(
  id: '$categoryId-$minor',
  type: TransactionType.expense,
  amount: Money.fromMinor(minor, 'RUB'),
  occurredOn: DateOnly(2026, 9, 5),
  occurredAt: DateTime.utc(2026, 9, 5, 9),
  categoryId: categoryId,
);

Future<void> _pump(WidgetTester tester, Size size, double scale) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 24, bottom: 24);
  tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 24);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
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
                _expense('a', 43000),
                _expense('b', 31000),
                _expense('c', 12000),
                _expense('d', 8000),
                _expense('e', 6000),
              ]),
              categories: Stream.value([
                for (final e in _names.entries)
                  Category.topLevel(
                    id: e.key,
                    kind: CategoryKind.expense,
                    name: e.value,
                    iconKey: 'icon',
                    sortOrder: 0,
                  ),
              ]),
              month: DateOnly(2026, 9, 20),
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
  await tester.pump();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
    await loadRoboto();
  });

  for (final size in const [Size(320, 640), Size(375, 667), Size(320, 711)]) {
    for (final scale in size.height == 711 ? [1.0] : [1.0, 1.3]) {
      testWidgets('${size.width.toInt()}x${size.height.toInt()}, '
          'шрифт ${(scale * 100).toInt()} %: без переполнения, легенда '
          'целиком, кнопки 56', (tester) async {
        await _pump(tester, size, scale);
        expect(tester.takeException(), isNull);

        // Легенда одной строкой-подписью: названия, проценты и «Ещё 2».
        final nbsp = String.fromCharCode(0x00A0);
        for (final text in ['Дом 43$nbsp%', 'Займы 31$nbsp%', 'Ещё 2']) {
          final finder = find.text(text);
          expect(finder, findsOneWidget, reason: text);
          final rect = tester.getRect(finder);
          expect(rect.left, greaterThanOrEqualTo(0), reason: text);
          expect(rect.right, lessThanOrEqualTo(size.width), reason: text);
        }
        // Цветных меток обычной легенды нет.
        expect(
          find.descendant(
            of: find.byType(MonthChartCard),
            matching: find.byType(ColorDot),
          ),
          findsNothing,
        );
        // Точки-разделители скринридер не читает.
        expect(
          find.ancestor(
            of: find.text('·'),
            matching: find.byType(ExcludeSemantics),
          ),
          findsWidgets,
        );
        // Озвучка элемента прежняя: название, сумма, процент.
        expect(
          find.bySemanticsLabel(RegExp('^Дом, .*, 43 процента\$')),
          findsOneWidget,
        );

        final button = tester.getSize(
          find
              .descendant(
                of: find.byType(HomeActionBar),
                matching: find.byType(FilledButton),
              )
              .first,
        );
        expect(button.height, 56);

        // Низ карточки достижим прокруткой и не уходит под кнопки.
        final scrollable = tester.state<ScrollableState>(
          find.descendant(
            of: find.byType(HomeScreen),
            matching: find.byType(Scrollable),
          ),
        );
        if (scrollable.position.maxScrollExtent > 0) {
          expect(find.byKey(HomeScreen.bottomFadeKey), findsOneWidget);
          scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
          await tester.pump();
          expect(find.byKey(HomeScreen.bottomFadeKey), findsNothing);
        } else {
          expect(find.byKey(HomeScreen.bottomFadeKey), findsNothing);
        }
        expect(
          tester.getRect(find.byType(MonthChartCard)).bottom,
          lessThanOrEqualTo(
            tester.getRect(find.byType(HomeActionBar)).top + 0.01,
          ),
        );
      });
    }
  }

  testWidgets('412x915, шрифт 130 %: обычный режим', (tester) async {
    await _pump(tester, const Size(412, 915), 1.3);
    expect(tester.takeException(), isNull);
    expect(find.text('Ещё 2'), findsNothing);
    expect(
      tester
          .getSize(
            find
                .descendant(
                  of: find.byType(HomeActionBar),
                  matching: find.byType(FilledButton),
                )
                .first,
          )
          .height,
      greaterThanOrEqualTo(64),
    );
  });

  testWidgets('412x915: обычный режим, легенда с метками, кнопки 64', (
    tester,
  ) async {
    await _pump(tester, const Size(412, 915), 1);
    expect(tester.takeException(), isNull);
    expect(find.text('Ещё 2'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(MonthChartCard),
        matching: find.byType(ColorDot),
      ),
      findsWidgets,
    );
    expect(find.byKey(HomeScreen.bottomFadeKey), findsNothing);
    final button = tester.getSize(
      find
          .descendant(
            of: find.byType(HomeActionBar),
            matching: find.byType(FilledButton),
          )
          .first,
    );
    expect(button.height, 64);
    expect(tester.getSize(find.byType(DonutChart)).width, 348);
  });
}
