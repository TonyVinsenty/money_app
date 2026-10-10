import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/app/app.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/quick_add/note_field.dart';
import 'package:money_app/features/transactions/presentation/quick_add/quick_add_screen.dart';
import 'package:money_app/features/transactions/presentation/quick_add/suggestion_row.dart';

import '../../../../support/fake_id_generator.dart';
import '../../../../support/fakes.dart';
import '../../../../support/fixed_clock.dart';

class _Transactions extends FakeTransactionsRepository {
  _Transactions(this.history);

  final List<Transaction> history;
  final added = <Transaction>[];
  DateRange? askedRange;

  @override
  Stream<List<Transaction>> watchInPeriod(
    DateRange period, {
    String currency = 'RUB',
  }) {
    askedRange = period;
    return Stream.value(history);
  }

  @override
  Future<void> add(Transaction transaction) async => added.add(transaction);

  @override
  Future<void> softDelete(String id) async {}
}

class _Categories extends FakeCategoriesRepository {
  _Categories(this.all);

  final List<Category> all;

  @override
  Stream<List<Category>> watchTopLevel(CategoryKind kind) => Stream.value([
    for (final c in all)
      if (c.kind == kind && c.isTopLevel) c,
  ]);

  @override
  Stream<List<Category>> watchAll() => Stream.value(all);
}

final _clock = FixedClock(DateTime(2026, 9, 20, 15, 30));

final _food = Category.topLevel(
  id: 'food',
  kind: CategoryKind.expense,
  name: 'Продукты',
  iconKey: 'shopping_cart',
  sortOrder: 0,
);
final _shop = Category.subcategoryOf(
  id: 'shop',
  parent: _food,
  name: 'Пятёрочка',
  iconKey: 'shopping_cart',
  sortOrder: 0,
);
final _cafe = Category.topLevel(
  id: 'cafe',
  kind: CategoryKind.expense,
  name: 'Кафе',
  iconKey: 'shopping_cart',
  sortOrder: 1,
);

var _n = 0;

List<Transaction> _history(
  Category category,
  Category? sub, {
  int count = 3,
  int hour = 15,
}) => [
  for (var i = 0; i < count; i++)
    Transaction(
      id: 'h${_n++}',
      type: TransactionType.expense,
      amount: Money.fromMinor(10000, 'RUB'),
      occurredOn: DateOnly(2026, 9, 10),
      occurredAt: DateTime(2026, 9, 10, hour).toUtc(),
      categoryId: category.id,
      subcategoryId: sub?.id,
    ),
];

Widget _app(_Transactions transactions) {
  final categories = _Categories([_food, _shop, _cafe]);
  return MaterialApp(
    theme: AppTheme.light(),
    locale: MoneyApp.appLocale,
    supportedLocales: MoneyApp.supportedLocales,
    localizationsDelegates: MoneyApp.localizationsDelegates,
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => QuickAddScreen(
                  type: TransactionType.expense,
                  clock: _clock,
                  categories: categories,
                  transactions: transactions,
                  idGenerator: FakeIdGenerator(),
                ),
              ),
            ),
            child: const Text('Открыть'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _toPicker(WidgetTester tester) async {
  await tester.tap(find.text('Открыть'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField), '350');
  await tester.tap(find.widgetWithText(FilledButton, 'Далее'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  testWidgets('нет истории: ряда нет, сетка на месте', (tester) async {
    await tester.pumpWidget(_app(_Transactions(const [])));
    await _toPicker(tester);
    expect(find.byType(SuggestionRow), findsNothing);
    expect(find.text('Продукты'), findsOneWidget);
    expect(find.text('Кафе'), findsOneWidget);
  });

  testWidgets('история за 90 дней: чип над сеткой, запрос за 90 дней', (
    tester,
  ) async {
    final repo = _Transactions(_history(_food, _shop));
    await tester.pumpWidget(_app(repo));
    await _toPicker(tester);
    expect(find.text('Продукты · Пятёрочка'), findsOneWidget);
    expect(repo.askedRange!.end, DateOnly(2026, 9, 20));
    expect(repo.askedRange!.start, DateOnly(2026, 9, 20).addDays(-90));
    // Чип выше сетки.
    expect(
      tester.getTopLeft(find.byType(SuggestionRow)).dy,
      lessThan(tester.getTopLeft(find.text('Кафе')).dy),
    );
  });

  testWidgets('тап по чипу сохраняет нужную пару с комментарием', (
    tester,
  ) async {
    final repo = _Transactions(_history(_food, _shop));
    await tester.pumpWidget(_app(repo));
    await _toPicker(tester);
    await tester.enterText(find.byType(NoteField), '  молоко ');
    await tester.tap(find.text('Продукты · Пятёрочка'));
    await tester.pumpAndSettle();

    final saved = repo.added.single;
    expect(saved.categoryId, 'food');
    expect(saved.subcategoryId, 'shop');
    expect(saved.note, 'молоко');
    expect(saved.amount, Money.fromMinor(35000, 'RUB'));
    final amountText = formatMoney(Money.fromMinor(35000, 'RUB'));
    expect(
      find.text('Сохранено: расход $amountText · Продукты · Пятёрочка'),
      findsOneWidget,
    );
    expect(find.text('Отменить'), findsOneWidget);
  });

  testWidgets('пара без подкатегории сохраняется без неё', (tester) async {
    final repo = _Transactions(_history(_cafe, null));
    await tester.pumpWidget(_app(repo));
    await _toPicker(tester);
    await tester.tap(find.widgetWithText(ActionChip, 'Кафе'));
    await tester.pumpAndSettle();
    expect(repo.added.single.categoryId, 'cafe');
    expect(repo.added.single.subcategoryId, isNull);
  });

  testWidgets('озвучка: «Сохранить: Продукты, Пятёрочка»', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_app(_Transactions(_history(_food, _shop))));
    await _toPicker(tester);
    expect(find.bySemanticsLabel('Сохранить: Продукты, Пятёрочка'), findsOne);
    handle.dispose();
  });

  testWidgets('360 dp и шрифт 200 %: чипы переносятся, ничего не обрезано', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final repo = _Transactions([
      ..._history(_food, _shop, count: 5),
      ..._history(_cafe, null, count: 4),
    ]);
    await tester.pumpWidget(_app(repo));
    await _toPicker(tester);

    expect(tester.takeException(), isNull);
    final chips = find.byType(ActionChip);
    expect(chips, findsNWidgets(2));
    for (final e in chips.evaluate()) {
      final box = e.renderObject! as RenderBox;
      final right = box.localToGlobal(Offset(box.size.width, 0)).dx;
      expect(right, lessThanOrEqualTo(360));
    }
  });
}
