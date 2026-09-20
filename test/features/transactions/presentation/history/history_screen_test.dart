import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/history/history_screen.dart';

final _today = DateOnly(2026, 9, 20);
final _minus = String.fromCharCode(0x2212);

Category _category(
  String id,
  String name, {
  CategoryKind kind = CategoryKind.expense,
  String? parentId,
  bool archived = false,
  String iconKey = 'shopping_cart',
}) {
  return Category(
    id: id,
    kind: kind,
    name: name,
    iconKey: iconKey,
    parentId: parentId,
    sortOrder: 0,
    archivedAt: archived ? DateTime.utc(2026, 9, 1) : null,
  );
}

Transaction _tx(
  String id,
  DateOnly day, {
  TransactionType type = TransactionType.expense,
  int minor = 35000,
  String categoryId = 'food',
  String? subcategoryId,
  String? note,
  int hour = 12,
}) {
  return Transaction(
    id: id,
    type: type,
    amount: Money.fromMinor(minor, 'RUB'),
    occurredOn: day,
    occurredAt: DateTime.utc(day.year, day.month, day.day, hour),
    categoryId: categoryId,
    subcategoryId: subcategoryId,
    note: note,
  );
}

final _categories = <Category>[
  _category('food', 'Продукты'),
  _category('shop', 'Пятёрочка', parentId: 'food'),
  _category('salary', 'Зарплата', kind: CategoryKind.income, iconKey: 'work'),
  _category('old', 'Старая категория', archived: true),
];

Widget _app({
  required Stream<List<Transaction>> transactions,
  Stream<List<Category>>? categories,
  ValueChanged<Transaction>? onTap,
  double textScale = 1,
  ThemeMode mode = ThemeMode.light,
}) {
  return MaterialApp(
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    themeMode: mode,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: HistoryScreen(
        transactions: transactions,
        categories: categories ?? Stream.value(_categories),
        today: _today,
        onTransactionTap: onTap ?? (_) {},
      ),
    ),
  );
}

Color? _colorOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  testWidgets('новые сверху, заголовки дней: Сегодня, Вчера, дата', (
    tester,
  ) async {
    final list = [
      _tx('a', _today, note: 'молоко'),
      _tx('b', _today, minor: 12000, categoryId: 'old', hour: 9),
      _tx(
        'c',
        DateOnly(2026, 9, 19),
        type: TransactionType.income,
        categoryId: 'salary',
      ),
      _tx('d', DateOnly(2026, 9, 15), minor: 500, categoryId: 'unknown'),
    ];
    await tester.pumpWidget(_app(transactions: Stream.value(list)));
    await tester.pumpAndSettle();

    expect(find.text('Сегодня'), findsOneWidget); // два дела в одном дне
    expect(find.text('Вчера'), findsOneWidget);
    expect(find.textContaining('15 сентября 2026'), findsOneWidget);

    // Порядок сверху вниз: заголовок, строки, следующий заголовок...
    double y(Finder f) => tester.getTopLeft(f).dy;
    final order = [
      y(find.text('Сегодня')),
      y(find.text('Продукты')),
      y(find.text('Старая категория')),
      y(find.text('Вчера')),
      y(find.text('Зарплата')),
      y(find.textContaining('15 сентября 2026')),
      y(find.text('Без категории')),
    ];
    expect(order, orderedEquals([...order]..sort()));
    expect(order.toSet(), hasLength(order.length));
  });

  testWidgets('у суммы знак и цвет типа; копейки всегда «,00»', (tester) async {
    final list = [
      _tx('a', _today), // расход 350
      _tx('b', _today, type: TransactionType.income, minor: 1000050),
      _tx('c', _today, minor: 0),
    ];
    await tester.pumpWidget(_app(transactions: Stream.value(list)));
    await tester.pumpAndSettle();

    final expense = '$_minus${formatMoney(Money.fromMinor(35000, 'RUB'))}';
    final income = '+${formatMoney(Money.fromMinor(1000050, 'RUB'))}';
    final zero = '$_minus${formatMoney(Money.zero('RUB'))}';

    expect(expense, contains('350,00'));
    expect(_colorOf(tester, expense), AppColors.light.expense);
    expect(income, contains('10${String.fromCharCode(0xA0)}000,50'));
    expect(_colorOf(tester, income), AppColors.light.income);
    expect(zero, contains('0,00'));
    expect(find.text(zero), findsOneWidget);
  });

  testWidgets('цвета суммы берутся из темы (тёмная тема)', (tester) async {
    final list = [_tx('a', _today)];
    await tester.pumpWidget(
      _app(transactions: Stream.value(list), mode: ThemeMode.dark),
    );
    await tester.pumpAndSettle();

    final expense = '$_minus${formatMoney(Money.fromMinor(35000, 'RUB'))}';
    expect(_colorOf(tester, expense), AppColors.dark.expense);
  });

  testWidgets('архивная категория, подкатегория и «Без категории»', (
    tester,
  ) async {
    final list = [
      _tx('a', _today, categoryId: 'old'),
      _tx('b', _today, subcategoryId: 'shop'),
      _tx('c', _today, categoryId: 'unknown'),
      // Подкатегории нет в справочнике: остаётся имя категории.
      _tx('d', _today, subcategoryId: 'lost'),
    ];
    await tester.pumpWidget(_app(transactions: Stream.value(list)));
    await tester.pumpAndSettle();

    expect(find.text('Старая категория'), findsOneWidget);
    expect(find.text('Продукты · Пятёрочка'), findsOneWidget);
    expect(find.text('Без категории'), findsOneWidget);
    expect(find.text('Продукты'), findsOneWidget);
  });

  testWidgets('комментарий вторым мелким текстом в одну строку', (
    tester,
  ) async {
    final list = [_tx('a', _today, note: 'молоко ' * 20)];
    await tester.pumpWidget(_app(transactions: Stream.value(list)));
    await tester.pumpAndSettle();

    final note = tester.widget<Text>(find.textContaining('молоко'));
    expect(note.maxLines, 1);
    expect(note.overflow, TextOverflow.ellipsis);
    final title = tester.getTopLeft(find.text('Продукты')).dy;
    expect(
      tester.getTopLeft(find.textContaining('молоко')).dy,
      greaterThan(title),
    );
    expect(
      note.style!.fontSize,
      lessThan(
        tester.widget<Text>(find.text('Продукты')).style!.fontSize ?? 99,
      ),
    );
  });

  testWidgets('строка: сводная подпись для скринридера и зона ≥ 48 dp', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final list = [
      _tx('a', _today, note: 'молоко'),
      _tx(
        'b',
        DateOnly(2026, 9, 19),
        type: TransactionType.income,
        minor: 100150,
      ),
    ];
    await tester.pumpWidget(_app(transactions: Stream.value(list)));
    await tester.pumpAndSettle();

    expect(
      find.bySemanticsLabel(
        'Расход 350 рублей, Продукты, Сегодня, комментарий: молоко',
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Доход 1001 рубль 50 копеек, Продукты, Вчера'),
      findsOneWidget,
    );
    final tiles = find.byType(InkWell);
    expect(tiles, findsNWidgets(2));
    for (var i = 0; i < 2; i++) {
      expect(tester.getSize(tiles.at(i)).height, greaterThanOrEqualTo(48));
    }
    handle.dispose();
  });

  testWidgets('тап по строке вызывает onTransactionTap с операцией', (
    tester,
  ) async {
    final tapped = <Transaction>[];
    final list = [_tx('a', _today), _tx('b', _today, categoryId: 'old')];
    await tester.pumpWidget(
      _app(transactions: Stream.value(list), onTap: tapped.add),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Старая категория'));
    expect(tapped.map((t) => t.id), ['b']);
  });

  testWidgets('операций нет: пустое состояние с подсказкой', (tester) async {
    await tester.pumpWidget(_app(transactions: Stream.value(const [])));
    await tester.pumpAndSettle();

    expect(find.text('Операций пока нет'), findsOneWidget);
    expect(
      find.text('Добавьте расход или доход на вкладке «Главная»'),
      findsOneWidget,
    );
    expect(find.byKey(historySkeletonKey), findsNothing);
  });

  testWidgets('до первого значения скелетон; пустое состояние не мигает', (
    tester,
  ) async {
    final cats = StreamController<List<Category>>();
    final txs = StreamController<List<Transaction>>();
    addTearDown(cats.close);
    addTearDown(txs.close);
    await tester.pumpWidget(
      _app(transactions: txs.stream, categories: cats.stream),
    );

    expect(find.byKey(historySkeletonKey), findsOneWidget);
    expect(find.text('Операций пока нет'), findsNothing);

    // Справочник пришёл, операции ещё нет: по-прежнему скелетон.
    cats.add(_categories);
    await tester.pumpAndSettle();
    expect(find.byKey(historySkeletonKey), findsOneWidget);
    expect(find.text('Операций пока нет'), findsNothing);

    // Операции пришли пустыми: только теперь «Операций пока нет».
    txs.add(const []);
    await tester.pumpAndSettle();
    expect(find.byKey(historySkeletonKey), findsNothing);
    expect(find.text('Операций пока нет'), findsOneWidget);

    // Появилась операция: список заменяет пустое состояние.
    txs.add([_tx('a', _today)]);
    await tester.pumpAndSettle();
    expect(find.text('Операций пока нет'), findsNothing);
    expect(find.text('Продукты'), findsOneWidget);
  });

  testWidgets('ошибка потока: общий текст AsyncView', (tester) async {
    await tester.pumpWidget(
      _app(transactions: Stream<List<Transaction>>.error(StateError('x'))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Не удалось загрузить данные'), findsOneWidget);
    expect(find.byKey(historySkeletonKey), findsNothing);
  });

  testWidgets('масштаб шрифта 200% на узком экране: без переполнения', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final list = [
      _tx(
        'a',
        _today,
        minor: 99999999999,
        subcategoryId: 'shop',
        note: 'очень длинный комментарий ' * 7,
      ),
      _tx('b', DateOnly(2026, 9, 1), categoryId: 'unknown', minor: 100),
    ];
    for (final scale in [1.0, 2.0]) {
      await tester.pumpWidget(
        _app(transactions: Stream.value(list), textScale: scale),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'scale $scale');
    }

    // Пустое состояние и скелетон тоже.
    await tester.pumpWidget(
      _app(transactions: Stream.value(const []), textScale: 2),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(
      _app(
        transactions: StreamController<List<Transaction>>().stream,
        categories: StreamController<List<Category>>().stream,
        textScale: 2,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
