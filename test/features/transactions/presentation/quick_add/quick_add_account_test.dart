import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/core/money/currency_catalog.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/quick_add/account_chip.dart';
import 'package:money_app/features/transactions/presentation/quick_add/quick_add_screen.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/fakes.dart';
import '../../../../support/fixed_clock.dart';

/// Плашка счёта в быстром вводе (шаг 5.13).
class _Transactions extends FakeTransactionsRepository {
  final added = <Transaction>[];

  @override
  Future<void> add(Transaction transaction) async => added.add(transaction);
}

class _Categories extends FakeCategoriesRepository {
  @override
  Stream<List<Category>> watchTopLevel(CategoryKind kind) => Stream.value([
    if (kind == CategoryKind.expense)
      Category.topLevel(
        id: 'a',
        kind: kind,
        name: 'Продукты',
        iconKey: 'shopping_cart',
        sortOrder: 0,
      ),
  ]);
}

Account _acc(
  String id,
  String name, {
  String currency = 'RUB',
  bool arch = false,
}) => Account(
  id: id,
  name: name,
  iconKey: 'card',
  openingBalance: Money.zero(currency),
  sortOrder: 0,
  currencyDigits: 2,
  archivedAt: arch ? DateTime.utc(2026, 9, 1) : null,
);

Future<_Transactions> _open(
  WidgetTester tester, {
  required List<Account> accounts,
  String? defaultId,
  String currency = 'RUB',
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final transactions = _Transactions();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      locale: MoneyApp.appLocale,
      supportedLocales: MoneyApp.supportedLocales,
      localizationsDelegates: MoneyApp.localizationsDelegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => QuickAddScreen(
                    type: TransactionType.expense,
                    clock: FixedClock(DateTime(2026, 9, 20, 15, 30)),
                    categories: _Categories(),
                    transactions: transactions,
                    idGenerator: FakeIdGenerator(),
                    currency: catalogCurrency(currency),
                    accounts: Stream.value(accounts),
                    defaultAccountId: defaultId,
                  ),
                ),
              ),
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Открыть'));
  await tester.pumpAndSettle();
  return transactions;
}

Future<void> _saveExpense(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField), '350');
  await tester.tap(find.widgetWithText(FilledButton, 'Далее'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Продукты'));
  await tester.pumpAndSettle();
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(AccountChip.chipKey));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  testWidgets('основной выбран заранее и попадает в операцию', (tester) async {
    final tx = await _open(
      tester,
      accounts: [_acc('a', 'Карта'), _acc('b', 'Наличные')],
      defaultId: 'a',
    );
    expect(find.text('Карта'), findsOneWidget);
    await _saveExpense(tester);
    expect(tx.added.single.accountId, 'a');
  });

  testWidgets('смена счёта и «Без счёта»', (tester) async {
    final tx = await _open(
      tester,
      accounts: [_acc('a', 'Карта'), _acc('b', 'Наличные')],
      defaultId: 'a',
    );
    await _openSheet(tester);
    await tester.tap(find.byKey(AccountChip.optionKey('b')));
    await tester.pumpAndSettle();
    expect(find.text('Наличные'), findsOneWidget);
    await _saveExpense(tester);
    expect(tx.added.single.accountId, 'b');

    final tx2 = await _open(
      tester,
      accounts: [_acc('a', 'Карта')],
      defaultId: 'a',
    );
    await _openSheet(tester);
    await tester.tap(find.byKey(AccountChip.optionKey(null)));
    await tester.pumpAndSettle();
    expect(find.text(accountChipNone), findsOneWidget);
    await _saveExpense(tester);
    expect(tx2.added.single.accountId, isNull);
  });

  testWidgets('нет основного: «Без счёта», операция без счёта', (tester) async {
    final tx = await _open(tester, accounts: [_acc('a', 'Карта')]);
    expect(find.text(accountChipNone), findsOneWidget);
    await _saveExpense(tester);
    expect(tx.added.single.accountId, isNull);
  });

  testWidgets('счетов нет - плашки нет, путь прежний', (tester) async {
    final tx = await _open(tester, accounts: const []);
    expect(find.byKey(AccountChip.chipKey), findsNothing);
    await _saveExpense(tester);
    expect(tx.added.single.accountId, isNull);
  });

  testWidgets('архивный в листе не предлагается', (tester) async {
    await _open(
      tester,
      accounts: [_acc('a', 'Карта'), _acc('z', 'Старая', arch: true)],
      defaultId: 'a',
    );
    await _openSheet(tester);
    expect(find.byKey(AccountChip.optionKey('a')), findsOneWidget);
    expect(find.byKey(AccountChip.optionKey('z')), findsNothing);
    expect(find.byKey(AccountChip.optionKey(null)), findsOneWidget);
  });

  testWidgets('основной RUB: счёт в USD не предлагается; только USD - плашки '
      'нет', (tester) async {
    await _open(
      tester,
      accounts: [
        _acc('a', 'Карта'),
        _acc('u', 'Доллары', currency: 'USD'),
      ],
      defaultId: 'a',
    );
    await _openSheet(tester);
    expect(find.byKey(AccountChip.optionKey('u')), findsNothing);
    expect(find.byKey(AccountChip.optionKey('a')), findsOneWidget);
  });

  testWidgets('только счета в другой валюте - плашки нет', (tester) async {
    await _open(
      tester,
      accounts: [_acc('u', 'Доллары', currency: 'USD')],
      defaultId: 'u',
    );
    expect(find.byKey(AccountChip.chipKey), findsNothing);
  });

  testWidgets('основная USD: предлагаются USD-счета', (tester) async {
    final tx = await _open(
      tester,
      accounts: [
        _acc('a', 'Карта'),
        _acc('u', 'Доллары', currency: 'USD'),
      ],
      defaultId: 'u',
      currency: 'USD',
    );
    expect(find.text('Доллары'), findsOneWidget);
    await _openSheet(tester);
    expect(find.byKey(AccountChip.optionKey('a')), findsNothing);
    await tester.tap(find.byKey(AccountChip.optionKey('u')));
    await tester.pumpAndSettle();
    await _saveExpense(tester);
    expect(tx.added.single.accountId, 'u');
  });

  testWidgets('плашка читается скринридером; шрифт 200 % без overflow', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _open(
      tester,
      accounts: [_acc('a', 'Карта')],
      defaultId: 'a',
      textScale: 2,
    );
    expect(find.bySemanticsLabel('Счёт: Карта, изменить'), findsOneWidget);
    expect(tester.takeException(), isNull);
    handle.dispose();
  });
}
