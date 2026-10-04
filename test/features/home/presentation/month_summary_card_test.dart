import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/home/presentation/month_summary_card.dart';

import '../../../support/contrast.dart';

Widget _app({
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
    // Как на «Главной»: боковой отступ 16 dp, карточка внутри прокрутки и
    // IntrinsicHeight (он не терпит LayoutBuilder внутри карточки).
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: IntrinsicHeight(
          child: MonthSummaryCard(
            expenses: expenses ?? Stream.value(Money.zero('RUB')),
            income: income ?? Stream.value(Money.zero('RUB')),
            month: DateOnly(2026, 10, 4),
          ),
        ),
      ),
    ),
  );
}

void _phone360(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

final _spoken = Money.fromMinor(1234550, 'RUB');
final _money = formatMoney(_spoken);

/// Сумма расхода со знаком «минус» (U+2212, не дефис).
const _expenseSign = '\u2212';

const _expenseKey = ValueKey('month-summary-expense');
const _incomeKey = ValueKey('month-summary-income');

Color _colorOf(WidgetTester tester, Finder text) =>
    tester.widget<Text>(text).style!.color!;

Finder _in(ValueKey<String> key, Finder matching) =>
    find.descendant(of: find.byKey(key), matching: matching);

/// Material внутри Card: в нём фактические цвет заливки и высота.
Material _material(WidgetTester tester) => tester.widget<Material>(
  find.descendant(of: find.byType(Card), matching: find.byType(Material)).first,
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  testWidgets('заголовок месяца по центру карточки', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    final card = tester.getRect(find.byType(Card));
    final title = tester.getRect(find.text('Октябрь 2026'));
    expect((title.center.dx - card.center.dx).abs(), lessThan(1));
  });

  testWidgets('одна карточка с рамкой без заливки, радиус 16 dp, без внешнего '
      'отступа', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pump();
    final scheme = Theme.of(tester.element(find.byType(MonthSummaryCard)))
        .colorScheme;

    expect(find.byType(Card), findsOneWidget);
    final card = tester.widget<Card>(find.byType(Card));
    expect(_material(tester).color, scheme.surface);
    expect(card.margin, EdgeInsets.zero);
    expect(_material(tester).elevation, 0);
    final shape = card.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(16));
    expect(shape.side.width, greaterThan(0));
  });

  testWidgets(
    'заголовок: месяц с заглавной буквы и год, цвет onSurfaceVariant',
    (tester) async {
      await tester.pumpWidget(_app());
      await tester.pump();

      final context = tester.element(find.byType(MonthSummaryCard));
      final title = find.text('Октябрь 2026');
      expect(title, findsOneWidget);
      expect(
        _colorOf(tester, title),
        Theme.of(context).colorScheme.onSurfaceVariant,
      );
    },
  );

  testWidgets('расход со знаком «минус» (U+2212), доход со знаком «+»', (
    tester,
  ) async {
    await tester.pumpWidget(_app(expenses: Stream.value(_spoken)));
    await tester.pump();
    expect(find.text('$_expenseSign$_money'), findsOneWidget);
    expect(find.textContaining('+'), findsNothing);

    await tester.pumpWidget(_app(income: Stream.value(_spoken)));
    await tester.pump();
    expect(find.text('+$_money'), findsOneWidget);
    expect(find.textContaining(_expenseSign), findsNothing);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('подписи нейтральные, суммы цветом своего типа ($mode)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          expenses: Stream.value(Money.fromMinor(60000, 'RUB')),
          income: Stream.value(Money.fromMinor(211000, 'RUB')),
          mode: mode,
        ),
      );
      await tester.pump();
      final context = tester.element(find.byType(MonthSummaryCard));
      final colors = context.appColors;
      final scheme = Theme.of(context).colorScheme;

      expect(
        _colorOf(tester, find.text('Расходы')),
        scheme.onSurfaceVariant,
        reason: 'подпись расходов',
      );
      expect(
        _colorOf(tester, find.text('Доходы')),
        scheme.onSurfaceVariant,
        reason: 'подпись доходов',
      );
      final expense = find.text(
        '$_expenseSign${formatMoney(Money.fromMinor(60000, 'RUB'))}',
      );
      final income = find.text(
        '+${formatMoney(Money.fromMinor(211000, 'RUB'))}',
      );
      expect(_colorOf(tester, expense), colors.expense);
      expect(_colorOf(tester, income), colors.income);
      expect(
        contrastRatio(scheme.onSurfaceVariant, scheme.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(colors.expense, scheme.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrastRatio(colors.income, scheme.surface),
        greaterThanOrEqualTo(4.5),
      );
    });

    testWidgets(
      'пустые итоги: «Пока нет» нейтральным цветом, без знаков ($mode)',
      (tester) async {
        await tester.pumpWidget(_app(mode: mode));
        await tester.pump();

        final context = tester.element(find.byType(MonthSummaryCard));
        final muted = Theme.of(context).colorScheme.onSurfaceVariant;
        for (final key in [_expenseKey, _incomeKey]) {
          final empty = _in(key, find.text('Пока нет'));
          expect(empty, findsOneWidget);
          expect(_colorOf(tester, empty), muted);
        }
        expect(find.textContaining('+'), findsNothing);
        expect(find.textContaining(_expenseSign), findsNothing);
      },
    );
  }

  testWidgets('360 dp, шрифт 100%: колонки в ряд, разделитель между ними', (
    tester,
  ) async {
    _phone360(tester);
    await tester.pumpWidget(
      _app(
        expenses: Stream.value(Money.fromMinor(60000, 'RUB')),
        income: Stream.value(Money.fromMinor(211000, 'RUB')),
      ),
    );
    await tester.pump();

    final left = tester.getRect(find.byKey(_expenseKey));
    final right = tester.getRect(find.byKey(_incomeKey));
    expect(left.top, right.top);
    expect(left.right, lessThan(right.left));
    expect(find.byType(VerticalDivider), findsOneWidget);
    // Суммы целиком, без сжатия: размер шрифта titleLarge.
    final text = tester.widget<Text>(
      find.text('+${formatMoney(Money.fromMinor(211000, 'RUB'))}'),
    );
    expect(text.style!.fontSize, 22);
    expect(tester.takeException(), isNull);
  });

  testWidgets('360 dp, шрифт 200%: колонки друг под другом, без переполнения', (
    tester,
  ) async {
    _phone360(tester);
    await tester.pumpWidget(
      _app(
        expenses: Stream.value(Money.fromMinor(123456789, 'RUB')),
        income: Stream.value(Money.fromMinor(987654321, 'RUB')),
        textScale: 2,
      ),
    );
    await tester.pump();

    final top = tester.getRect(find.byKey(_expenseKey));
    final bottom = tester.getRect(find.byKey(_incomeKey));
    expect(top.bottom, lessThanOrEqualTo(bottom.top));
    expect(find.byType(VerticalDivider), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('узкий экран 240 dp при 100%: тоже столбик', (tester) async {
    tester.view.physicalSize = const Size(240, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    await tester.pump();

    expect(find.byType(VerticalDivider), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('все состояния при шрифте 200% на узком экране: без '
      'переполнения', (tester) async {
    tester.view.physicalSize = const Size(240, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final states = <Stream<Money> Function()>[
      () => Stream.value(Money.fromMinor(987654321, 'RUB')),
      () => Stream.value(Money.zero('RUB')),
      () => Stream.error(StateError('boom')),
    ];
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final total in states) {
        await tester.pumpWidget(
          _app(expenses: total(), income: total(), mode: mode, textScale: 2),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: '$mode');
      }
    }
  });

  testWidgets('ошибка: иконка error, текст нейтральный; вторая колонка цела', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        expenses: Stream.error(StateError('boom')),
        income: Stream.value(_spoken),
      ),
    );
    await tester.pump();

    final context = tester.element(find.byType(MonthSummaryCard));
    final scheme = Theme.of(context).colorScheme;
    final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
    expect(icon.color, scheme.error);
    expect(
      _colorOf(tester, find.text('Не удалось посчитать расходы за месяц')),
      scheme.onSurfaceVariant,
    );
    expect(find.text('+$_money'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('скринридер: каждая колонка одним узлом, сумма прописью', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(expenses: Stream.value(_spoken), income: Stream.value(_spoken)),
    );
    await tester.pump();

    expect(
      find.bySemanticsLabel('Расходы за октябрь: 12345 рублей 50 копеек'),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel('Доходы за октябрь: 12345 рублей 50 копеек'),
      findsOneWidget,
    );
    // Знак «минус» в озвучке не появляется, отдельных узлов у подписей нет.
    expect(find.bySemanticsLabel(RegExp(_expenseSign)), findsNothing);
    expect(find.bySemanticsLabel('Расходы'), findsNothing);
    semantics.dispose();
  });

  testWidgets('до первого значения только подпись; потом «Пока нет»', (
    tester,
  ) async {
    final controller = StreamController<Money>();
    addTearDown(controller.close);
    await tester.pumpWidget(_app(income: controller.stream));
    await tester.pump();

    expect(_in(_incomeKey, find.text('Доходы')), findsOneWidget);
    expect(_in(_incomeKey, find.text('Пока нет')), findsNothing);

    controller.add(Money.zero('RUB'));
    await tester.pump();
    await tester.pump();
    expect(_in(_incomeKey, find.text('Пока нет')), findsOneWidget);
  });
}
