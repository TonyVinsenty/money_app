import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/home/presentation/home_screen.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';
import 'package:money_app/features/transactions/presentation/quick_add/saved_snack_bar.dart';

Widget _app({
  required void Function(TransactionType) onAdd,
  Stream<Money>? expenses,
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
        month: DateOnly(2026, 9, 20),
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

/// Отношение контрастности двух цветов (WCAG).
double _contrast(Color a, Color b) {
  final l1 = a.computeLuminance();
  final l2 = b.computeLuminance();
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

void main() {
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

  testWidgets('зона нажатия каждой кнопки не меньше 48x48 (высота 56)', (
    tester,
  ) async {
    await tester.pumpWidget(_app(onAdd: (_) {}));

    for (final label in ['Доход', 'Расход']) {
      final size = tester.getSize(_button(label));
      expect(size.width, greaterThanOrEqualTo(48), reason: label);
      expect(size.height, greaterThanOrEqualTo(56), reason: label);
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
      final surface = Theme.of(tester.element(find.byType(HomeScreen)))
          .colorScheme
          .surface;

      final incomeStyle = _styleOf(tester, 'Доход');
      final expenseStyle = _styleOf(tester, 'Расход');
      expect(incomeStyle.backgroundColor?.resolve({}), colors.income);
      expect(expenseStyle.backgroundColor?.resolve({}), colors.expense);
      expect(
        colors,
        mode == ThemeMode.light ? AppColors.light : AppColors.dark,
      );

      for (final style in [incomeStyle, expenseStyle]) {
        final background = style.backgroundColor!.resolve({})!;
        final foreground = style.foregroundColor!.resolve({})!;
        expect(foreground, surface);
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

  group('итог расходов за месяц', () {
    setUpAll(() async {
      await initializeDateFormatting('ru');
    });

    final emptyText = find.text('В этом месяце расходов ещё нет');
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
      expect(
        find.text(
          'Расходы за сентябрь: ${formatMoney(Money.fromMinor(1234500, 'RUB'))}',
        ),
        findsOneWidget,
      );
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

      // 12 345,00 ₽ (пробел разряда и перед ₽ неразрывные, формат общий).
      expect(
        find.text(
          'Расходы за сентябрь: ${formatMoney(Money.fromMinor(1234500, 'RUB'))}',
        ),
        findsOneWidget,
      );
      expect(emptyText, findsNothing);
    });

    testWidgets('нулевой итог: пустое состояние', (tester) async {
      await tester.pumpWidget(_app(onAdd: (_) {}));
      await tester.pump();

      expect(emptyText, findsOneWidget);
      expect(find.textContaining('Расходы за'), findsNothing);
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
              month: DateOnly(2026, 9, 20),
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
}
