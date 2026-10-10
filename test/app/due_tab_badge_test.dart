import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/app/app_shell.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/domain/recurring_repository.dart';
import 'package:money_app/features/recurring/presentation/due_tab_badge.dart';
import 'package:money_app/features/recurring/presentation/recurring_texts.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

RecurringDue _due(int i) => RecurringDue(
  id: 'd$i',
  payment: RecurringPayment(
    id: 'p$i',
    title: 'Платёж $i',
    type: TransactionType.expense,
    amount: Money.fromMinor(1000, 'RUB'),
    categoryId: 'cat',
    unit: RepeatUnit.month,
    every: 1,
    startsOn: DateOnly(2026, 10, 10),
  ),
  dueOn: DateOnly(2026, 10, 10),
  status: RecurringDueStatus.pending,
);

/// Нижняя панель каркаса с вкладкой «Баланс», у которой значок с кружком.
Widget _host(ValueNotifier<List<RecurringDue>> dues, {double scale = 1}) {
  final tabs = <AppTab>[
    AppTab(
      label: 'Главная',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home,
      builder: (_) => const SizedBox(),
    ),
    AppTab(
      label: 'История',
      icon: Icons.receipt_long_outlined,
      selectedIcon: Icons.receipt_long,
      builder: (_) => const SizedBox(),
    ),
    AppTab(
      label: 'Баланс',
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet,
      builder: (_) => const SizedBox(),
      decorateIcon: (context, icon) => DueTabBadge(dues: dues, icon: icon),
    ),
  ];
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: AppShell(tabs: tabs),
  );
}

void main() {
  testWidgets('0 записей: кружка нет', (tester) async {
    final dues = ValueNotifier<List<RecurringDue>>(const []);
    addTearDown(dues.dispose);
    await tester.pumpWidget(_host(dues));
    expect(find.byKey(DueTabBadge.badgeKey), findsNothing);
  });

  testWidgets('1 и 3 записи: число; все оплачены - кружок исчез', (
    tester,
  ) async {
    final dues = ValueNotifier([_due(1)]);
    addTearDown(dues.dispose);
    await tester.pumpWidget(_host(dues));
    expect(
      find.descendant(
        of: find.byKey(DueTabBadge.badgeKey),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    dues.value = [_due(1), _due(2), _due(3)];
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(DueTabBadge.badgeKey),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    dues.value = const [];
    await tester.pump();
    expect(find.byKey(DueTabBadge.badgeKey), findsNothing);
  });

  testWidgets('больше 99: «99+»', (tester) async {
    final dues = ValueNotifier([for (var i = 0; i < 100; i++) _due(i)]);
    addTearDown(dues.dispose);
    await tester.pumpWidget(_host(dues));
    expect(find.text('99+'), findsOneWidget);
    expect(dueBadgeText(5), '5');
  });

  testWidgets('озвучка вкладки: «Баланс, к оплате: 3»', (tester) async {
    final handle = tester.ensureSemantics();
    final dues = ValueNotifier([_due(1), _due(2), _due(3)]);
    addTearDown(dues.dispose);
    await tester.pumpWidget(_host(dues));
    final node = tester.getSemantics(
      find
          .ancestor(of: find.text('Баланс'), matching: find.byType(Semantics))
          .first,
    );
    // Подпись вкладки и значение «к оплате: 3»: читаются как «Баланс, к оплате: 3».
    expect(node.label, startsWith('Баланс'));
    expect(node.value, dueBadgeSemantics(3));
    handle.dispose();
  });

  testWidgets('шрифт 200 %: панель не ломается', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dues = ValueNotifier([_due(1), _due(2), _due(3)]);
    addTearDown(dues.dispose);
    await tester.pumpWidget(_host(dues, scale: 2));
    expect(find.byKey(DueTabBadge.badgeKey), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
