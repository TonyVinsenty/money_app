import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/home/presentation/home_screen.dart';
import 'package:money_app/features/home/presentation/month_chart_card.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/quick_add/saved_snack_bar.dart';

import '../../../support/contrast.dart';

Widget _app({
  required void Function(TransactionType) onAdd,
  Stream<Money>? expenses,
  Stream<Money>? income,
  ThemeMode mode = ThemeMode.light,
  double textScale = 1,
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
      body: HomeScreen(
        onAddTransaction: onAdd,
        monthExpenses: expenses ?? Stream.value(Money.zero('RUB')),
        monthIncome: income ?? Stream.value(Money.zero('RUB')),
        monthTransactions: Stream.value(const []),
        categories: Stream.value(const []),
        month: DateOnly(2026, 9, 20),
        onOpenCategory: (_) {},
      ),
    ),
  );
}

/// Кнопка, внутри которой лежит подпись [label].
Finder _button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.bySubtype<FilledButton>(),
);

ButtonStyle _styleOf(WidgetTester tester, String label) =>
    tester.widget<FilledButton>(_button(label)).style!;

double _contrast(Color a, Color b) => contrastRatio(a, b);

const _expenseCard = ValueKey('month-summary-expense');
const _incomeCard = ValueKey('month-summary-income');

/// Текст [text] внутри карточки итога [card].
Finder _inCard(ValueKey<String> card, String text) =>
    find.descendant(of: find.byKey(card), matching: find.text(text));

/// Сумма расхода со знаком «минус» (U+2212, не дефис).
String _expenseSum(int minor) =>
    '\u2212${formatMoney(Money.fromMinor(minor, 'RUB'))}';

void main() {
  // Подпись итога содержит название месяца: без русской локали даже пустое
  // состояние не строится.
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  testWidgets('две кнопки с подписями словом и знаками', (tester) async {
    await tester.pumpWidget(_app(onAdd: (_) {}));

    expect(_button('Доход'), findsOneWidget);
    expect(_button('Расход'), findsOneWidget);
    expect(
      find.descendant(of: _button('Доход'), matching: find.byIcon(Icons.add)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _button('Расход'),
        matching: find.byIcon(Icons.remove),
      ),
      findsOneWidget,
    );
  });

  testWidgets('тап вызывает onAddTransaction с нужным типом по разу', (
    tester,
  ) async {
    final calls = <TransactionType>[];
    await tester.pumpWidget(_app(onAdd: calls.add));

    await tester.tap(find.text('Доход'));
    expect(calls, [TransactionType.income]);

    await tester.tap(find.text('Расход'));
    expect(calls, [TransactionType.income, TransactionType.expense]);
  });

  testWidgets('зона нажатия каждой кнопки не меньше 48x48 (высота 64)', (
    tester,
  ) async {
    await tester.pumpWidget(_app(onAdd: (_) {}));

    for (final label in ['Доход', 'Расход']) {
      final size = tester.getSize(_button(label));
      expect(size.width, greaterThanOrEqualTo(48), reason: label);
      expect(size.height, 64, reason: label);
    }
  });

  testWidgets('кнопки в одном ряду: «Доход» слева от «Расход»', (tester) async {
    await tester.pumpWidget(_app(onAdd: (_) {}));

    final income = tester.getRect(_button('Доход'));
    final expense = tester.getRect(_button('Расход'));
    expect(
      tester.getTopLeft(_button('Доход')).dy,
      tester.getTopLeft(_button('Расход')).dy,
    );
    expect(income.right, lessThanOrEqualTo(expense.left));
  });

  testWidgets('кнопки со скруглением 16 dp', (tester) async {
    await tester.pumpWidget(_app(onAdd: (_) {}));

    for (final label in ['Доход', 'Расход']) {
      final shape =
          _styleOf(tester, label).shape!.resolve({})! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(16), reason: label);
    }
  });

  testWidgets('подписи для скринридера и действие нажатия', (tester) async {
    final semantics = tester.ensureSemantics();
    final calls = <TransactionType>[];
    await tester.pumpWidget(_app(onAdd: calls.add));

    expect(find.bySemanticsLabel('Добавить доход'), findsOneWidget);
    expect(find.bySemanticsLabel('Добавить расход'), findsOneWidget);
    // Скринридер не читает отдельно слово и иконку: только общую подпись.
    expect(find.bySemanticsLabel('Доход'), findsNothing);
    expect(find.bySemanticsLabel('Расход'), findsNothing);

    final node = tester.getSemantics(find.bySemanticsLabel('Добавить расход'));
    expect(node.flagsCollection.isButton, isTrue);
    // Нажатие «как скринридером» (двойной тап) тоже срабатывает.
    tester.semantics.tap(find.semantics.byLabel('Добавить доход'));
    expect(calls, [TransactionType.income]);

    semantics.dispose();
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('цвета кнопок из темы ($mode), контраст текста не ниже 4.5', (
      tester,
    ) async {
      await tester.pumpWidget(_app(onAdd: (_) {}, mode: mode));
      final colors = tester.element(find.byType(HomeScreen)).appColors;

      final incomeStyle = _styleOf(tester, 'Доход');
      final expenseStyle = _styleOf(tester, 'Расход');
      expect(incomeStyle.backgroundColor?.resolve({}), colors.incomeAction);
      expect(expenseStyle.backgroundColor?.resolve({}), colors.expenseAction);
      expect(
        colors,
        mode == ThemeMode.light ? AppColors.light : AppColors.dark,
      );

      // Текст кнопки — светлый цвет из палитры, а не цвет поверхности темы.
      expect(incomeStyle.foregroundColor?.resolve({}), colors.onIncomeAction);
      expect(expenseStyle.foregroundColor?.resolve({}), colors.onExpenseAction);

      for (final style in [incomeStyle, expenseStyle]) {
        final background = style.backgroundColor!.resolve({})!;
        final foreground = style.foregroundColor!.resolve({})!;
        expect(_contrast(foreground, background), greaterThanOrEqualTo(4.5));
      }
    });
  }

  testWidgets('узкий экран и крупный шрифт: нет переполнения', (tester) async {
    tester.view.physicalSize = const Size(240, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(onAdd: (_) {}, textScale: 2));

    expect(tester.takeException(), isNull);
    expect(find.text('Доход'), findsOneWidget);
    expect(find.text('Расход'), findsOneWidget);
  });

  testWidgets('карточки итогов растянуты на всю ширину экрана без отступов', (
    tester,
  ) async {
    // Пустые итоги (узкий контент): без растягивания карточка сжалась бы по
    // тексту. Ширина экрана минус отступы 16 с каждой стороны.
    await tester.pumpWidget(_app(onAdd: (_) {}));
    await tester.pump();

    final available = tester.getSize(find.byType(HomeScreen)).width - 32;
    expect(
      tester.getSize(find.byKey(_expenseCard)).width,
      closeTo(available, 0.5),
    );
    expect(
      tester.getSize(find.byKey(_incomeCard)).width,
      closeTo(available, 0.5),
    );
  });

  group('итог расходов за месяц', () {
    setUpAll(() async {
      await initializeDateFormatting('ru');
    });

    final emptyText = _inCard(_expenseCard, 'Пока нет');
    final errorText = find.text('Не удалось посчитать расходы за месяц');

    testWidgets('до первого значения нет ни итога, ни пустого состояния', (
      tester,
    ) async {
      final controller = StreamController<Money>();
      addTearDown(controller.close);
      await tester.pumpWidget(_app(onAdd: (_) {}, expenses: controller.stream));
      await tester.pump();

      expect(find.textContaining('Расходы за'), findsNothing);
      expect(emptyText, findsNothing);
      expect(errorText, findsNothing);

      // Пришло значение: итог появился, «пусто» не мелькало.
      controller.add(Money.fromMinor(1234500, 'RUB'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Расходы за сентябрь'), findsOneWidget);
      expect(find.text(_expenseSum(1234500)), findsOneWidget);
      expect(emptyText, findsNothing);
    });

    testWidgets('итог: месяц словом и сумма как в остальном приложении', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          onAdd: (_) {},
          expenses: Stream.value(Money.fromMinor(1234500, 'RUB')),
        ),
      );
      await tester.pump();

      // Подпись и сумма — разные строки; сумма 12 345,00 ₽ с минусом.
      expect(find.text('Расходы за сентябрь'), findsOneWidget);
      expect(find.text(_expenseSum(1234500)), findsOneWidget);
      expect(emptyText, findsNothing);
    });

    testWidgets('нулевой итог: пустое состояние', (tester) async {
      await tester.pumpWidget(_app(onAdd: (_) {}));
      await tester.pump();

      expect(emptyText, findsOneWidget);
      expect(find.text('Расходы за сентябрь'), findsOneWidget);
    });

    testWidgets('ошибка потока: короткий текст, без падения', (tester) async {
      await tester.pumpWidget(
        _app(onAdd: (_) {}, expenses: Stream.error(StateError('boom'))),
      );
      await tester.pump();

      expect(errorText, findsOneWidget);
      expect(emptyText, findsNothing);
      expect(tester.takeException(), isNull);
      // Кнопки при ошибке остаются рабочими.
      expect(find.text('Расход'), findsOneWidget);
    });

    testWidgets('скринридер читает сумму прописью', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          onAdd: (_) {},
          expenses: Stream.value(Money.fromMinor(1234550, 'RUB')),
        ),
      );
      await tester.pump();

      expect(
        find.bySemanticsLabel('Расходы за сентябрь: 12345 рублей 50 копеек'),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('итог доходов за месяц', () {
    setUpAll(() async {
      await initializeDateFormatting('ru');
    });

    final emptyText = _inCard(_incomeCard, 'Пока нет');
    final errorText = find.text('Не удалось посчитать доходы за месяц');
    final money = formatMoney(Money.fromMinor(1234500, 'RUB'));

    testWidgets('строка под расходами: знак «+», месяц и сумма', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          onAdd: (_) {},
          expenses: Stream.value(Money.fromMinor(50000, 'RUB')),
          income: Stream.value(Money.fromMinor(1234500, 'RUB')),
        ),
      );
      await tester.pump();

      final incomeSum = find.text('+$money');
      expect(incomeSum, findsOneWidget);
      expect(find.text('Доходы за сентябрь'), findsOneWidget);
      expect(emptyText, findsNothing);
      // Раскладка: карточка «Расходов» выше карточки «Доходов».
      expect(
        tester.getTopLeft(find.text('Расходы за сентябрь')).dy,
        lessThan(tester.getTopLeft(find.text('Доходы за сентябрь')).dy),
      );
    });

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('цвет дохода из темы ($mode), контраст не ниже 4.5', (
        tester,
      ) async {
        await tester.pumpWidget(
          _app(
            onAdd: (_) {},
            mode: mode,
            income: Stream.value(Money.fromMinor(1234500, 'RUB')),
          ),
        );
        await tester.pump();

        final context = tester.element(find.byType(HomeScreen));
        final text = tester.widget<Text>(find.text('+$money'));
        final color = text.style!.color!;
        expect(color, context.appColors.income);
        expect(
          _contrast(color, Theme.of(context).colorScheme.surface),
          greaterThanOrEqualTo(4.5),
        );
      });
    }

    testWidgets('до первого значения нет ни суммы, ни пустого состояния', (
      tester,
    ) async {
      final controller = StreamController<Money>();
      addTearDown(controller.close);
      await tester.pumpWidget(_app(onAdd: (_) {}, income: controller.stream));
      await tester.pump();

      expect(find.textContaining('Доходы за'), findsNothing);
      expect(emptyText, findsNothing);
      expect(errorText, findsNothing);

      controller.add(Money.fromMinor(1234500, 'RUB'));
      await tester.pump();
      await tester.pump();
      expect(find.text('+$money'), findsOneWidget);
      expect(find.text('Доходы за сентябрь'), findsOneWidget);
      expect(emptyText, findsNothing);
    });

    testWidgets('нулевой итог: пустое состояние, расходы не затронуты', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          onAdd: (_) {},
          expenses: Stream.value(Money.fromMinor(50000, 'RUB')),
        ),
      );
      await tester.pump();

      expect(emptyText, findsOneWidget);
      expect(find.text('Доходы за сентябрь'), findsOneWidget);
      expect(find.textContaining('Расходы за сентябрь'), findsOneWidget);
    });

    testWidgets('ошибка потока доходов: короткий текст, расходы целы', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          onAdd: (_) {},
          expenses: Stream.value(Money.fromMinor(50000, 'RUB')),
          income: Stream.error(StateError('boom')),
        ),
      );
      await tester.pump();

      expect(errorText, findsOneWidget);
      expect(find.textContaining('Расходы за сентябрь'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('скринридер читает сумму прописью, без знака и символа', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          onAdd: (_) {},
          income: Stream.value(Money.fromMinor(1234550, 'RUB')),
        ),
      );
      await tester.pump();

      expect(
        find.bySemanticsLabel('Доходы за сентябрь: 12345 рублей 50 копеек'),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('масштаб шрифта 200% на узком экране: без переполнения', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(240, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await tester.pumpWidget(
          _app(
            onAdd: (_) {},
            mode: mode,
            textScale: 2,
            expenses: Stream.value(Money.fromMinor(123456789, 'RUB')),
            income: Stream.value(Money.fromMinor(987654321, 'RUB')),
          ),
        );
        // Смена темы плавная: ждём конца анимации, иначе тёмная тема не
        // успеет примениться.
        await tester.pumpAndSettle();

        expect(
          Theme.of(tester.element(find.byType(HomeScreen))).brightness,
          mode == ThemeMode.dark ? Brightness.dark : Brightness.light,
        );
        expect(tester.takeException(), isNull, reason: '$mode');
        expect(
          find.textContaining('Расходы за'),
          findsOneWidget,
          reason: '$mode',
        );
        expect(
          find.textContaining('Доходы за'),
          findsOneWidget,
          reason: '$mode',
        );
        expect(find.text('Расход'), findsOneWidget, reason: '$mode');
      }
    });
  });

  group('место под SnackBar', () {
    // Экран целиком: каркас, нижняя панель и сообщение после сохранения.
    Widget appWithBar(List<TransactionType> calls, {double textScale = 1}) {
      return MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SafeArea(
            bottom: false,
            child: HomeScreen(
              onAddTransaction: calls.add,
              monthExpenses: Stream.value(Money.fromMinor(35000, 'RUB')),
              monthIncome: Stream.value(Money.fromMinor(100000, 'RUB')),
              monthTransactions: Stream.value(const []),
              categories: Stream.value(const []),
              month: DateOnly(2026, 9, 20),
              onOpenCategory: (_) {},
            ),
          ),
          bottomNavigationBar: NavigationBar(
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home), label: 'Главная'),
              NavigationDestination(icon: Icon(Icons.list), label: 'История'),
            ],
          ),
        ),
      );
    }

    // Настоящее сообщение из быстрого ввода: тот же размер, что увидит человек.
    Future<void> showSnackBar(WidgetTester tester) async {
      ScaffoldMessenger.of(tester.element(find.byType(HomeScreen)))
          .showSnackBar(
            SavedSnackBar.build(
              text:
                  'Сохранено: расход '
                  '${formatMoney(Money.fromMinor(35000, 'RUB'))} · Продукты',
              spokenText: 'Сохранено: расход 350 рублей · Продукты',
              onUndo: () {},
            ),
          );
      await tester.pumpAndSettle();
    }

    void useSmallPhone(WidgetTester tester) {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('кнопки выше сообщения, тап проходит в кнопку', (tester) async {
      useSmallPhone(tester);
      final calls = <TransactionType>[];
      await tester.pumpWidget(appWithBar(calls));
      await tester.pump();
      await showSnackBar(tester);

      expect(find.byType(SnackBar), findsOneWidget);
      final snackTop = tester.getRect(find.byType(SnackBar)).top;
      for (final label in ['Доход', 'Расход']) {
        expect(
          tester.getRect(_button(label)).bottom,
          lessThanOrEqualTo(snackTop),
          reason: '$label не должна попадать под сообщение',
        );
      }

      // Тап доходит до кнопки, а не до сообщения (иначе вызовов было бы 0).
      await tester.tap(find.text('Расход'));
      await tester.tap(find.text('Доход'));
      expect(calls, [TransactionType.expense, TransactionType.income]);
    });

    testWidgets('шрифт 200% на 360x640: нет переполнения, кнопки на месте', (
      tester,
    ) async {
      useSmallPhone(tester);
      await tester.pumpWidget(appWithBar([], textScale: 2));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await showSnackBar(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Доход'), findsOneWidget);
      expect(find.text('Расход'), findsOneWidget);
    });
  });

  testWidgets('карточка диаграммы занимает середину: между итогами и кнопками', (
    tester,
  ) async {
    await tester.pumpWidget(_app(onAdd: (_) {}));
    await tester.pump();

    final card = tester.getRect(find.byType(MonthChartCard));
    final summary = tester.getRect(find.byKey(_incomeCard));
    final buttons = tester.getRect(_button('Доход'));
    expect(card.top, greaterThanOrEqualTo(summary.bottom));
    // Карточка доходит до отступа 16 dp над кнопками: середина занята целиком.
    expect(card.bottom, closeTo(buttons.top - 16, 0.5));
  });

  testWidgets('шрифт 200% на 360 dp: подписи кнопок целиком внутри кнопок', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_app(onAdd: (_) {}, textScale: 2));
    await tester.pump();

    expect(tester.takeException(), isNull);
    for (final label in ['Доход', 'Расход']) {
      final button = tester.getRect(_button(label));
      final text = tester.getRect(find.text(label));
      expect(text.left, greaterThanOrEqualTo(button.left), reason: label);
      expect(text.right, lessThanOrEqualTo(button.right), reason: label);
    }
  });
}
