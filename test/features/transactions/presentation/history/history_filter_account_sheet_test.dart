import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/history_view.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/history/history_screen.dart';

final _today = DateOnly(2026, 9, 30);

final _categories = <Category>[
  Category(
    id: 'food',
    kind: CategoryKind.expense,
    name: 'Продукты',
    iconKey: 'shopping_cart',
    parentId: null,
    sortOrder: 0,
  ),
];

Transaction _tx(String id, String note, {String? accountId}) => Transaction(
  id: id,
  type: TransactionType.expense,
  amount: Money.fromMinor(10000, 'RUB'),
  occurredOn: DateOnly(2026, 9, 12),
  occurredAt: DateTime.utc(2026, 9, 12, 12),
  categoryId: 'food',
  note: note,
  accountId: accountId,
);

final _list = [
  _tx('t1', 'по-карте', accountId: 'card'),
  _tx('t2', 'по-кошельку', accountId: 'cash'),
  _tx('t3', 'без-счёта'),
];

Account _account(
  String id,
  String name,
  int order, {
  String currency = 'RUB',
  bool archived = false,
}) => Account(
  id: id,
  name: name,
  iconKey: 'wallet',
  openingBalance: Money.fromMinor(0, currency),
  sortOrder: order,
  currencyDigits: 2,
  archivedAt: archived ? DateTime.utc(2026, 9, 1) : null,
);

class _Harness extends StatefulWidget {
  const _Harness({required this.accounts, this.initial = HistoryFilter.off});

  final List<Account> accounts;
  final HistoryFilter initial;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late HistoryFilter filter = widget.initial;
  final transactions = Stream.value(_list).asBroadcastStream();
  final categories = Stream.value(_categories).asBroadcastStream();
  late final accounts = Stream.value(widget.accounts).asBroadcastStream();

  @override
  Widget build(BuildContext context) => HistoryScreen(
    transactions: transactions,
    categories: categories,
    accounts: accounts,
    today: _today,
    month: _today,
    hasAnyTransactions: true,
    onTransactionTap: (_) {},
    filter: filter,
    onResetFilter: () => setState(() => filter = HistoryFilter.off),
    onFilterChanged: (f) => setState(() => filter = f),
  );
}

Future<void> _pump(
  WidgetTester tester,
  List<Account> accounts, {
  HistoryFilter initial = HistoryFilter.off,
  double textScale = 1,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: _Harness(accounts: accounts, initial: initial),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Фильтр'));
  await tester.pumpAndSettle();
}

final _card = _account('card', 'Карта', 0);
final _cash = _account('cash', 'Наличные', 1);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('HistoryFilter: счёт', () {
    final withCard = Transaction(
      id: 'x',
      type: TransactionType.expense,
      amount: Money.fromMinor(100, 'RUB'),
      occurredOn: DateOnly(2026, 9, 1),
      occurredAt: DateTime.utc(2026, 9, 1),
      categoryId: 'food',
      accountId: 'card',
    );
    final other = _tx('y', 'n', accountId: 'cash');
    final none = _tx('z', 'n');
    final income = Transaction(
      id: 'i',
      type: TransactionType.income,
      amount: Money.fromMinor(100, 'RUB'),
      occurredOn: DateOnly(2026, 9, 1),
      occurredAt: DateTime.utc(2026, 9, 1),
      categoryId: 'salary',
    );

    test('«Без счёта» - только операции без счёта', () {
      final f = HistoryFilter(withoutAccount: true);
      expect(f.isActive, isTrue);
      expect([withCard, other, none, income].where(f.matches), [none, income]);
    });

    test('счёт - только его операции', () {
      final f = HistoryFilter.account('card');
      expect([withCard, other, none].where(f.matches), [withCard]);
    });

    test('«Все счета» - все операции', () {
      expect([withCard, other, none].where(HistoryFilter.off.matches), [
        withCard,
        other,
        none,
      ]);
    });

    test('вместе с типом и категориями', () {
      final f = HistoryFilter(
        type: HistoryTypeFilter.expense,
        expenseCategoryIds: {'food'},
        withoutAccount: true,
      );
      expect([withCard, none, income].where(f.matches), [none]);
      final g = HistoryFilter(
        type: HistoryTypeFilter.expense,
        expenseCategoryIds: {'cafe'},
        withoutAccount: true,
      );
      expect([none].where(g.matches), isEmpty);
    });

    test('равенство и hashCode трёх состояний', () {
      final all = HistoryFilter.off;
      final none1 = HistoryFilter(withoutAccount: true);
      final none2 = HistoryFilter(withoutAccount: true);
      final one = HistoryFilter.account('card');
      expect(none1, none2);
      expect(none1.hashCode, none2.hashCode);
      expect(none1, isNot(all));
      expect(none1, isNot(one));
      expect(all, isNot(one));
      expect(one, HistoryFilter(accountId: 'card'));
    });

    test('счёт и «без счёта» вместе недопустимы', () {
      expect(
        () => HistoryFilter(accountId: 'card', withoutAccount: true),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('Раздел «Счёт» в листе', () {
    testWidgets('есть при счетах основной валюты, с пометкой архива', (
      tester,
    ) async {
      await _pump(tester, [
        _card,
        _account('old', 'Старая', 5, archived: true),
        _account('usd', 'Доллары', 2, currency: 'USD'),
      ]);
      await _openSheet(tester);
      expect(find.text('Счёт'), findsOneWidget);
      expect(find.text('Все счета'), findsOneWidget);
      expect(find.text('Карта'), findsOneWidget);
      expect(find.text('Старая (в архиве)'), findsOneWidget);
      expect(find.text('Без счёта'), findsOneWidget);
      expect(find.text('Доллары'), findsNothing);
    });

    testWidgets('нет без счетов основной валюты', (tester) async {
      await _pump(tester, [_account('usd', 'Доллары', 2, currency: 'USD')]);
      await _openSheet(tester);
      expect(find.text('Фильтр'), findsWidgets);
      expect(find.text('Все счета'), findsNothing);
      expect(find.text('Без счёта'), findsNothing);
    });

    testWidgets('выбор счёта, «Без счёта» и «Сбросить»', (tester) async {
      await _pump(tester, [_card, _cash]);
      await _openSheet(tester);

      await tester.tap(find.text('Наличные'));
      await tester.pumpAndSettle();
      expect(find.text('Фильтр: Счёт: Наличные'), findsOneWidget);

      await tester.tap(find.text('Без счёта'));
      await tester.pumpAndSettle();
      expect(find.text('Фильтр: Без счёта'), findsOneWidget);

      await tester.tap(find.text('Сбросить').last);
      await tester.pumpAndSettle();
      expect(find.text('Фильтр: Без счёта'), findsNothing);
      expect(find.text('Фильтр: Счёт: Наличные'), findsNothing);

      await tester.tap(find.text('Карта'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Все счета'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Фильтр: '), findsNothing);
    });

    testWidgets('«Без счёта» оставляет в списке только операции без счёта', (
      tester,
    ) async {
      await _pump(tester, [_card, _cash]);
      await _openSheet(tester);
      await tester.tap(find.text('Без счёта'));
      await tester.pumpAndSettle();
      expect(find.text('Фильтр: Без счёта'), findsOneWidget);
      expect(find.text('без-счёта'), findsOneWidget);
      expect(find.text('по-карте'), findsNothing);
      expect(find.text('по-кошельку'), findsNothing);
    });

    testWidgets('временный фильтр счёта показан в листе выбранным', (
      tester,
    ) async {
      await _pump(tester, [
        _card,
        _cash,
      ], initial: HistoryFilter.account('card'));
      await _openSheet(tester);
      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Карта'),
      );
      expect(tile.selected, isTrue);
      final all = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Все счета'),
      );
      expect(all.selected, isFalse);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets('360 dp, шрифт ${scale * 100} % - без переполнения', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(360, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await _pump(tester, [
          _card,
          _account(
            'old',
            'Очень длинное название старого счёта',
            3,
            archived: true,
          ),
        ], textScale: scale);
        await _openSheet(tester);
        expect(find.text('Все счета'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
