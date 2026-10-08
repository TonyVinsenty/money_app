import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/edit/edit_transaction_screen.dart';
import 'package:money_app/features/transactions/presentation/quick_add/account_chip.dart';

import '../../../../support/fakes.dart';
import '../../../../support/fixed_clock.dart';

/// Строка «Счёт» в правке операции (шаг 5.14).
class _Transactions extends FakeTransactionsRepository {
  _Transactions(this.original);

  final Transaction original;
  final updated = <Transaction>[];

  @override
  Future<Transaction?> findById(String id) async => original;

  @override
  Future<void> update(Transaction transaction) async =>
      updated.add(transaction);
}

class _Categories extends FakeCategoriesRepository {
  @override
  Future<Category?> findById(String id) async => Category.topLevel(
    id: id,
    kind: CategoryKind.expense,
    name: 'Продукты',
    iconKey: 'shopping_cart',
    sortOrder: 0,
  );
}

Transaction _tx({String? accountId, String currency = 'RUB'}) => Transaction(
  id: 'tx',
  type: TransactionType.expense,
  amount: Money.fromMinor(35000, currency),
  occurredOn: DateOnly(2026, 9, 18),
  occurredAt: DateTime.utc(2026, 9, 18, 7, 45),
  categoryId: 'food',
  accountId: accountId,
);

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
  required Transaction transaction,
  required List<Account> accounts,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = _Transactions(transaction);
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
                  builder: (_) => EditTransactionScreen(
                    transaction: transaction,
                    clock: FixedClock(DateTime(2026, 9, 20, 15, 30)),
                    categories: _Categories(),
                    transactions: repo,
                    accounts: Stream.value(accounts),
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
  return repo;
}

Finder get _row => find.byKey(EditTransactionScreen.accountRowKey);

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(FilledButton, 'Сохранить'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  testWidgets('смена счёта сохраняется в операции', (tester) async {
    final repo = await _open(
      tester,
      transaction: _tx(accountId: 'a'),
      accounts: [_acc('a', 'Карта'), _acc('b', 'Наличные')],
    );
    expect(find.text('Карта'), findsOneWidget);
    await tester.tap(_row);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(accountOptionKey('b')));
    await tester.pumpAndSettle();
    expect(find.text('Наличные'), findsOneWidget);
    await _save(tester);
    expect(repo.updated.single.accountId, 'b');
  });

  testWidgets('«Без счёта» снимает счёт; без счёта можно выбрать', (
    tester,
  ) async {
    final repo = await _open(
      tester,
      transaction: _tx(accountId: 'a'),
      accounts: [_acc('a', 'Карта')],
    );
    await tester.tap(_row);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(accountOptionKey(null)));
    await tester.pumpAndSettle();
    expect(find.text(accountChipNone), findsOneWidget);
    await _save(tester);
    expect(repo.updated.single.accountId, isNull);

    final repo2 = await _open(
      tester,
      transaction: _tx(),
      accounts: [_acc('a', 'Карта')],
    );
    expect(find.text(accountChipNone), findsOneWidget);
    await tester.tap(_row);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(accountOptionKey('a')));
    await tester.pumpAndSettle();
    await _save(tester);
    expect(repo2.updated.single.accountId, 'a');
  });

  testWidgets('архивный счёт операции: «(в архиве)», сохраняется без '
      'изменений, в листе его нет', (tester) async {
    final repo = await _open(
      tester,
      transaction: _tx(accountId: 'z'),
      accounts: [_acc('z', 'Карта', arch: true), _acc('a', 'Наличные')],
    );
    expect(find.text('Карта (в архиве)'), findsOneWidget);
    await _save(tester);
    expect(repo.updated.single.accountId, 'z');

    await _open(
      tester,
      transaction: _tx(accountId: 'z'),
      accounts: [_acc('z', 'Карта', arch: true), _acc('a', 'Наличные')],
    );
    await tester.tap(_row);
    await tester.pumpAndSettle();
    expect(find.byKey(accountOptionKey('z')), findsNothing);
    expect(find.byKey(accountOptionKey('a')), findsOneWidget);
  });

  testWidgets('в листе только счета валюты операции', (tester) async {
    await _open(
      tester,
      transaction: _tx(currency: 'USD'),
      accounts: [
        _acc('a', 'Карта'),
        _acc('u', 'Доллары', currency: 'USD'),
      ],
    );
    await tester.tap(_row);
    await tester.pumpAndSettle();
    expect(find.byKey(accountOptionKey('a')), findsNothing);
    expect(find.byKey(accountOptionKey('u')), findsOneWidget);
  });

  testWidgets('нет счетов валюты операции и нет счёта у операции - строки '
      'нет', (tester) async {
    await _open(
      tester,
      transaction: _tx(),
      accounts: [_acc('u', 'Доллары', currency: 'USD')],
    );
    expect(_row, findsNothing);
  });

  testWidgets('шрифт 200 %: без переполнения', (tester) async {
    await _open(
      tester,
      transaction: _tx(accountId: 'a'),
      accounts: [_acc('a', 'Очень длинное название кредитной карты')],
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    expect(_row, findsOneWidget);
  });
}
