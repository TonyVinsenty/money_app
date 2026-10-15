import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/format/day_label.dart';
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

import '../../../../support/nbsp.dart';

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
  bool? hasAny = false,
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
        month: _today,
        hasAnyTransactions: hasAny,
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

  testWidgets('месяц пуст, firstDay неизвестен: загрузка, не «Операций нет»', (
    tester,
  ) async {
    await tester.pumpWidget(_app(transactions: Stream.value([]), hasAny: null));
    await tester.pump();
    await tester.pump();

    expect(find.text('Здесь будут все ваши доходы и расходы'), findsNothing);
    expect(find.bySemanticsLabel('Загрузка операций'), findsOneWidget);
  });

  testWidgets(
    'firstDay ответил null: «Здесь будут все ваши доходы и расходы»',
    (tester) async {
      await tester.pumpWidget(
        _app(transactions: Stream.value([]), hasAny: null),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('Здесь будут все ваши доходы и расходы'), findsNothing);

      await tester.pumpWidget(
        _app(transactions: Stream.value([]), hasAny: false),
      );
      await tester.pump();
      await tester.pump();
      expect(
        find.text('Здесь будут все ваши доходы и расходы'),
        findsOneWidget,
      );
    },
  );

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
    expect(find.text('Вторник, 15$dateNbspсентября'), findsOneWidget);

    // Порядок сверху вниз: заголовок, строки, следующий заголовок...
    double y(Finder f) => tester.getTopLeft(f).dy;
    final order = [
      y(find.text('Сегодня')),
      y(find.text('Продукты')),
      y(find.text('Старая категория')),
      y(find.text('Вчера')),
      y(find.text('Зарплата')),
      y(find.text('Вторник, 15$dateNbspсентября')),
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

  testWidgets('строка с категорией glyph:Ж показывает букву', (tester) async {
    final cats = [_category('z', 'Жильё', iconKey: 'glyph:Ж')];
    await tester.pumpWidget(
      _app(
        transactions: Stream.value([_tx('a', _today, categoryId: 'z')]),
        categories: Stream.value(cats),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ж'), findsOneWidget);
    expect(find.byIcon(Icons.category_outlined), findsNothing);
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
    final tiles = find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(InkWell),
    );
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

  group('пустая «История» (У4)', () {
    Widget screen({
      bool? hasAny = false,
      VoidCallback? onAdd,
      String query = '',
      double textScale = 1,
    }) => MaterialApp(
      theme: AppTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: HistoryScreen(
          transactions: Stream.value(const []),
          categories: Stream.value(_categories),
          today: _today,
          month: _today,
          hasAnyTransactions: hasAny,
          onTransactionTap: (_) {},
          onAddExpense: onAdd,
          searchQuery: query,
          onSearchChanged: (_) {},
        ),
      ),
    );

    testWidgets('операций нет: текст и «Добавить расход», поиска нет', (
      tester,
    ) async {
      var added = 0;
      await tester.pumpWidget(screen(onAdd: () => added++));
      await tester.pumpAndSettle();

      expect(find.text(historyEmptyTitle), findsOneWidget);
      expect(find.byKey(historySkeletonKey), findsNothing);
      expect(find.byType(TextField), findsNothing);
      final button = find.widgetWithText(FilledButton, historyAddExpenseLabel);
      expect(button, findsOneWidget);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      await tester.tap(button);
      expect(added, 1);
    });

    testWidgets('без обработчика кнопки нет', (tester) async {
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(find.text(historyEmptyTitle), findsOneWidget);
      expect(find.text(historyAddExpenseLabel), findsNothing);
    });

    testWidgets('операции есть, месяц пуст: прежний текст, поиск есть', (
      tester,
    ) async {
      await tester.pumpWidget(screen(hasAny: true, onAdd: () {}));
      await tester.pumpAndSettle();
      expect(find.text('Выберите другой месяц стрелками вверху'), findsOne);
      expect(find.text(historyEmptyTitle), findsNothing);
      expect(find.text(historyAddExpenseLabel), findsNothing);
      // Поле за лупой (И2): лупа есть, поля пока нет.
      expect(find.byTooltip(historySearchTooltip), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('поиск начат, а база опустела: поле остаётся', (tester) async {
      await tester.pumpWidget(screen(query: 'кофе', onAdd: () {}));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('360 dp, шрифт 200 %: без переполнения', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(screen(onAdd: () {}, textScale: 2));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text(historyAddExpenseLabel), findsOneWidget);
    });
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
    expect(find.text('Здесь будут все ваши доходы и расходы'), findsNothing);

    // Справочник пришёл, операции ещё нет: по-прежнему скелетон.
    cats.add(_categories);
    await tester.pumpAndSettle();
    expect(find.byKey(historySkeletonKey), findsOneWidget);
    expect(find.text('Здесь будут все ваши доходы и расходы'), findsNothing);

    // Операции пришли пустыми: только теперь «Здесь будут все ваши доходы и расходы».
    txs.add(const []);
    await tester.pumpAndSettle();
    expect(find.byKey(historySkeletonKey), findsNothing);
    expect(find.text('Здесь будут все ваши доходы и расходы'), findsOneWidget);

    // Появилась операция: список заменяет пустое состояние.
    txs.add([_tx('a', _today)]);
    await tester.pumpAndSettle();
    expect(find.text('Здесь будут все ваши доходы и расходы'), findsNothing);
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

  testWidgets('линия под «Фильтр»: нет вверху списка, есть после прокрутки', (
    tester,
  ) async {
    final list = [
      for (var i = 0; i < 40; i++) _tx('t$i', _today, minor: 100 + i),
    ];
    await tester.pumpWidget(_app(transactions: Stream.value(list)));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(historyScrolledDividerKey), findsNothing);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pump();
    expect(find.byKey(historyScrolledDividerKey), findsOneWidget);
    final line = tester.getSize(find.byKey(historyScrolledDividerKey));
    expect(line.height, 1);
    final scheme = Theme.of(tester.element(find.byType(CustomScrollView)))
        .colorScheme;
    expect(
      tester.widget<ColoredBox>(find.byKey(historyScrolledDividerKey)).color,
      scheme.outlineVariant,
    );

    // Вернулись к началу: линия снова скрыта.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 2000));
    await tester.pumpAndSettle();
    expect(find.byKey(historyScrolledDividerKey), findsNothing);
  });

  group('поиск за лупой (И2, шаг 8.42)', () {
    /// Экран с запросом снаружи (как в приложении): запрос переживает
    /// пересоздание экрана; [shown] — показан ли экран (смена вкладки).
    Widget searchable({
      required ValueNotifier<String> query,
      bool shown = true,
    }) => MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: !shown
            ? const SizedBox.shrink()
            : ValueListenableBuilder<String>(
                valueListenable: query,
                builder: (context, value, _) => HistoryScreen(
                  transactions: Stream.value([
                    _tx('a', _today, note: 'кофе'),
                    _tx('b', _today, note: 'хлеб'),
                  ]),
                  categories: Stream.value(_categories),
                  today: _today,
                  month: _today,
                  hasAnyTransactions: true,
                  onTransactionTap: (_) {},
                  searchQuery: value,
                  onSearchChanged: (text) => query.value = text,
                ),
              ),
      ),
    );

    testWidgets('поля нет до касания лупы; касание — поле с фокусом', (
      tester,
    ) async {
      final query = ValueNotifier('');
      addTearDown(query.dispose);
      await tester.pumpWidget(searchable(query: query));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      // Лупа — в строке «Фильтр».
      final lupa = find.byTooltip(historySearchTooltip);
      expect(lupa, findsOneWidget);
      expect(
        tester.getCenter(lupa).dy,
        moreOrLessEquals(tester.getCenter(find.text('Фильтр')).dy, epsilon: 2),
      );

      await tester.tap(lupa);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byTooltip(historySearchTooltip), findsNothing);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode!.hasFocus, isTrue);
      // Пустое поле: крестик закрывает.
      expect(find.byTooltip(historySearchCloseTooltip), findsOneWidget);
    });

    testWidgets('поиск работает как раньше', (tester) async {
      final query = ValueNotifier('');
      addTearDown(query.dispose);
      await tester.pumpWidget(searchable(query: query));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(historySearchTooltip));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'коф');
      await tester.pumpAndSettle();
      expect(query.value, 'коф');
      expect(find.text('кофе'), findsOneWidget);
      expect(find.text('хлеб'), findsNothing);
    });

    testWidgets('с текстом поле остаётся и после смены вкладки', (
      tester,
    ) async {
      final query = ValueNotifier('');
      addTearDown(query.dispose);
      await tester.pumpWidget(searchable(query: query));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(historySearchTooltip));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'хлеб');
      await tester.pumpAndSettle();

      // Ушли на другую вкладку и вернулись: экран построен заново.
      await tester.pumpWidget(searchable(query: query, shown: false));
      await tester.pumpWidget(searchable(query: query));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'хлеб',
      );
    });

    testWidgets('крестик очищает и прячет поле, месяц вернулся', (
      tester,
    ) async {
      final query = ValueNotifier('');
      addTearDown(query.dispose);
      await tester.pumpWidget(searchable(query: query));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(historySearchTooltip));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'хлеб');
      await tester.pumpAndSettle();
      expect(find.text('Во всех месяцах'), findsOneWidget);

      await tester.tap(find.byTooltip(historySearchClearTooltip));
      await tester.pumpAndSettle();
      expect(query.value, '');
      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip(historySearchTooltip), findsOneWidget);
      expect(find.text('Во всех месяцах'), findsNothing);
      expect(find.text('кофе'), findsOneWidget);
    });

    testWidgets('пустое поле прячется, когда из него ушли', (tester) async {
      final query = ValueNotifier('');
      addTearDown(query.dispose);
      await tester.pumpWidget(searchable(query: query));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(historySearchTooltip));
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.byTooltip(historySearchTooltip), findsOneWidget);
    });

    testWidgets('без обработчика поиска лупы нет', (tester) async {
      await tester.pumpWidget(
        _app(transactions: Stream.value([_tx('a', _today)]), hasAny: true),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip(historySearchTooltip), findsNothing);
    });
  });

  group('закреплённые заголовки дней (И3, шаг 8.43)', () {
    /// Три дня по 12 операций.
    final days = [_today, _today.addDays(-1), _today.addDays(-2)];
    final list = [
      for (final (d, day) in days.indexed)
        for (var i = 0; i < 12; i++)
          _tx('d${d}_$i', day, minor: 1000 + i, hour: 20 - i),
    ];
    // Подписи — лениво: данные дат для «ru» готовятся в setUpAll.
    List<String> labels() => [
      for (final day in days) historyDayLabel(day, today: _today),
    ];

    double listTop(WidgetTester tester) =>
        tester.getTopLeft(find.byType(CustomScrollView)).dy;

    Future<void> pumpList(WidgetTester tester, {double textScale = 1}) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _app(transactions: Stream.value(list), textScale: textScale),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('при прокрутке заголовок текущего дня — наверху', (
      tester,
    ) async {
      await pumpList(tester);
      expect(tester.getTopLeft(find.text(labels()[0])).dy, greaterThan(0));

      // Прокрутили в середину первого дня: его заголовок прижат к верху.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      final header = find.ancestor(
        of: find.text(labels()[0]),
        matching: find.byType(PinnedHeaderSliver),
      );
      expect(header, findsOneWidget);
      expect(
        tester.getTopLeft(find.text(labels()[0])).dy,
        lessThan(listTop(tester) + 24),
      );
      expect(
        tester.getTopLeft(find.text(labels()[0])).dy,
        greaterThanOrEqualTo(listTop(tester)),
      );
    });

    testWidgets('следующий день выталкивает предыдущий заголовок', (
      tester,
    ) async {
      await pumpList(tester);
      // Подводим заголовок второго дня почти к верху списка.
      final top = listTop(tester);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      final second = tester.getTopLeft(find.text(labels()[1])).dy;
      await tester.drag(
        find.byType(CustomScrollView),
        Offset(0, -(second - top - 10)),
      );
      await tester.pumpAndSettle();
      // Первый заголовок уехал вверх ровно настолько, насколько его поджал
      // второй: низ первого = верх второго (в пределах отступов заголовка).
      final firstRect = tester.getRect(
        find
            .ancestor(
              of: find.text(labels()[0]),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      final secondRect = tester.getRect(
        find
            .ancestor(
              of: find.text(labels()[1]),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(firstRect.bottom, moreOrLessEquals(secondRect.top, epsilon: 1));
      expect(firstRect.top, lessThan(top));

      // Дальше — второй заголовок прижат к верху, первого не видно.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text(labels()[1])).dy,
        lessThan(listTop(tester) + 24),
      );
      final firstNow = find.text(labels()[0]);
      if (firstNow.evaluate().isNotEmpty) {
        expect(tester.getBottomLeft(firstNow).dy, lessThanOrEqualTo(top));
      }
    });

    testWidgets('у заголовка фон экрана: строки под ним не просвечивают', (
      tester,
    ) async {
      await pumpList(tester);
      final box = tester.widget<ColoredBox>(
        find
            .ancestor(
              of: find.text(labels()[0]),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      final scheme = Theme.of(tester.element(find.text(labels()[0])))
          .colorScheme;
      expect(box.color, scheme.surface);
    });

    testWidgets('200 %: закреплённый заголовок не обрезан', (tester) async {
      await pumpList(tester, textScale: 2);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final text = tester.getRect(find.text(labels()[0]));
      final box = tester.getRect(
        find
            .ancestor(
              of: find.text(labels()[0]),
              matching: find.byType(ColoredBox),
            )
            .first,
      );
      expect(box.top, lessThanOrEqualTo(text.top));
      expect(box.bottom, greaterThanOrEqualTo(text.bottom));
      expect(text.top, greaterThanOrEqualTo(listTop(tester)));
    });
  });
}
