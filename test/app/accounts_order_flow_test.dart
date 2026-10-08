import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app_routes.dart';
import 'package:money_app/app/app_scope.dart';
import 'package:money_app/app/balance_tab.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/ui/category_rule_text.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/presentation/account_texts.dart';
import 'package:money_app/features/accounts/presentation/accounts_order_screen.dart';
import 'package:money_app/features/accounts/presentation/accounts_section.dart';
import 'package:money_app/features/settings/presentation/app_settings_controller.dart';

import '../support/fakes.dart';

/// Экран «Порядок счетов» (шаг 5.12b).
Account _acc(String id, String name, int order, {bool archived = false}) =>
    Account(
      id: id,
      name: name,
      iconKey: 'card',
      openingBalance: Money.zero('RUB'),
      sortOrder: order,
      currencyDigits: 2,
      archivedAt: archived ? DateTime.utc(2026, 9, 1) : null,
    );

Future<void> _pump(
  WidgetTester tester,
  InMemoryAccountsRepository repo, {
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final settings = AppSettingsController();
  addTearDown(settings.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      onGenerateRoute: onGenerateAppRoute,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: AppScope(
        services: fakeAppServices(settings: settings, accounts: repo),
        child: const Scaffold(body: BalanceTab()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _openOrder(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(AccountsSection.orderKey));
  await tester.tap(find.byKey(AccountsSection.orderKey));
  await tester.pumpAndSettle();
}

double _y(WidgetTester tester, String name) =>
    tester.getTopLeft(find.text(name)).dy;

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  final threeAccounts = [
    _acc('a', 'Карта', 0),
    _acc('b', 'Наличные', 1),
    _acc('c', 'Копилка', 2),
  ];

  testWidgets('один активный счёт - пункта нет; архивные не считаются', (
    tester,
  ) async {
    await _pump(
      tester,
      InMemoryAccountsRepository([
        _acc('a', 'Карта', 0),
        _acc('b', 'Старая', 1, archived: true),
      ]),
    );
    expect(find.byKey(AccountsSection.orderKey), findsNothing);
  });

  testWidgets('перестановка сохраняется и видна на вкладке', (tester) async {
    final repo = InMemoryAccountsRepository(threeAccounts);
    await _pump(tester, repo);
    expect(_y(tester, 'Карта'), lessThan(_y(tester, 'Наличные')));

    await _openOrder(tester);
    expect(find.text(accountsOrderHint), findsOneWidget);
    // «Карту» тянем за ручку вниз, ниже «Наличных».
    final handle = find.descendant(
      of: find.byKey(AccountsOrderScreen.rowKey('a')),
      matching: find.byIcon(Icons.drag_handle),
    );
    await _dragDown(tester, handle);
    await tester.pumpAndSettle();
    expect(repo.reorderCalls.single, ['b', 'a', 'c']);
    expect(repo.all.map((a) => a.id), ['b', 'a', 'c']);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(_y(tester, 'Наличные'), lessThan(_y(tester, 'Карта')));
    expect(_y(tester, 'Карта'), lessThan(_y(tester, 'Копилка')));
  });

  testWidgets('в списке только активные счета; у строки есть действия', (
    tester,
  ) async {
    final repo = InMemoryAccountsRepository([
      ...threeAccounts,
      _acc('d', 'Старая', 3, archived: true),
    ]);
    await _pump(tester, repo);
    await _openOrder(tester);
    expect(find.byKey(AccountsOrderScreen.rowKey('d')), findsNothing);
    final handle = tester.ensureSemantics();
    final data = tester
        .getSemantics(find.byKey(AccountsOrderScreen.rowKey('b')))
        .getSemanticsData();
    expect(data.customSemanticsActionIds, isNotEmpty);
    handle.dispose();
  });

  testWidgets('сбой записи: прежний порядок и сообщение', (tester) async {
    final repo = InMemoryAccountsRepository(threeAccounts);
    await _pump(tester, repo);
    await _openOrder(tester);
    repo.failWith = Exception('boom');
    final handle = find.descendant(
      of: find.byKey(AccountsOrderScreen.rowKey('a')),
      matching: find.byIcon(Icons.drag_handle),
    );
    await _dragDown(tester, handle);
    await tester.pumpAndSettle();
    expect(find.text(categorySaveFailedText), findsOneWidget);
    expect(_y(tester, 'Карта'), lessThan(_y(tester, 'Наличные')));
  });

  testWidgets('360 dp и шрифт 200 %: без переполнения', (tester) async {
    final repo = InMemoryAccountsRepository([
      _acc('a', 'Очень длинное название кредитной карты', 0),
      _acc('b', 'Наличные', 1),
    ]);
    await _pump(tester, repo, textScale: 2);
    expect(tester.takeException(), isNull);
    await _openOrder(tester);
    expect(tester.takeException(), isNull);
    expect(find.text(accountsOrderTitle), findsWidgets);
  });
}

/// Тянет ручку вниз на строку с двумя паузами, как делает палец.
Future<void> _dragDown(WidgetTester tester, Finder handle) async {
  final gesture = await tester.startGesture(tester.getCenter(handle));
  await gesture.moveBy(const Offset(0, 20));
  await tester.pump();
  await gesture.moveBy(const Offset(0, 100));
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}
