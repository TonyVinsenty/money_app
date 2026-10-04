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
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/contrast.dart';

Widget _app({
  required TransactionType type,
  required Stream<Money> total,
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
    // Как на «Главной»: карточка лежит внутри прокрутки, поэтому при крупном
    // шрифте она растёт по высоте, а не переполняет экран.
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: MonthSummaryCard(
          type: type,
          total: total,
          month: DateOnly(2026, 9, 20),
        ),
      ),
    ),
  );
}

final _money = formatMoney(Money.fromMinor(1234500, 'RUB'));
final _spoken = Money.fromMinor(1234550, 'RUB');

/// Сумма расхода со знаком «минус» (U+2212, не дефис).
const _expenseSign = '\u2212';

Color _colorOf(WidgetTester tester, Finder text) =>
    tester.widget<Text>(text).style!.color!;

/// Material внутри Card: в нём фактические цвет заливки и высота.
Material _material(WidgetTester tester) => tester.widget<Material>(
  find.descendant(of: find.byType(Card), matching: find.byType(Material)).first,
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ru');
  });

  testWidgets('расход и доход — обе карточки с рамкой без заливки, радиус 16 '
      'dp, без внешнего отступа', (tester) async {
    for (final type in TransactionType.values) {
      await tester.pumpWidget(_app(type: type, total: Stream.value(_spoken)));
      await tester.pump();
      final scheme = Theme.of(tester.element(find.byType(MonthSummaryCard)))
          .colorScheme;

      final card = tester.widget<Card>(find.byType(Card));
      // Цвет и высота у Card берутся из темы при сборке, поэтому смотрим на
      // фактические значения внутри карточки (Material).
      expect(_material(tester).color, scheme.surface, reason: '$type');
      expect(card.margin, EdgeInsets.zero, reason: '$type');
      expect(_material(tester).elevation, 0, reason: '$type');
      final shape = card.shape! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(16), reason: '$type');
      expect(shape.side.width, greaterThan(0), reason: '$type');
    }
  });

  testWidgets('без FittedBox: длинная сумма переносится, а не сжимается', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        type: TransactionType.expense,
        total: Stream.value(Money.fromMinor(123456789, 'RUB')),
      ),
    );
    await tester.pump();

    expect(find.byType(FittedBox), findsNothing);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('пустой доход: «Пока нет» нейтральным цветом, не цветом '
        'дохода ($mode)', (tester) async {
      await tester.pumpWidget(
        _app(
          type: TransactionType.income,
          total: Stream.value(Money.zero('RUB')),
          mode: mode,
        ),
      );
      await tester.pump();

      final context = tester.element(find.byType(MonthSummaryCard));
      final muted = Theme.of(context).colorScheme.onSurfaceVariant;
      final empty = find.text('Пока нет');
      expect(empty, findsOneWidget);
      expect(_colorOf(tester, empty), muted);
      expect(_colorOf(tester, empty), isNot(context.appColors.income));
      // Подпись сверху без суммы и без знака «+».
      expect(find.text('Доходы за сентябрь'), findsOneWidget);
      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('пустой расход: «Пока нет» нейтральным цветом, без знака и '
        'красного ($mode)', (tester) async {
      await tester.pumpWidget(
        _app(
          type: TransactionType.expense,
          total: Stream.value(Money.zero('RUB')),
          mode: mode,
        ),
      );
      await tester.pump();

      final context = tester.element(find.byType(MonthSummaryCard));
      final empty = find.text('Пока нет');
      expect(empty, findsOneWidget);
      expect(
        _colorOf(tester, empty),
        Theme.of(context).colorScheme.onSurfaceVariant,
      );
      expect(_colorOf(tester, empty), isNot(context.appColors.expense));
      expect(find.text('Расходы за сентябрь'), findsOneWidget);
      expect(find.textContaining(_expenseSign), findsNothing);
    });
  }

  testWidgets('расход со знаком «минус» (U+2212), доход со знаком «+»', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(type: TransactionType.expense, total: Stream.value(_spoken)),
    );
    await tester.pump();
    expect(find.text('$_expenseSign${formatMoney(_spoken)}'), findsOneWidget);

    await tester.pumpWidget(
      _app(type: TransactionType.income, total: Stream.value(_spoken)),
    );
    await tester.pump();
    expect(find.text('+${formatMoney(_spoken)}'), findsOneWidget);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('подпись нейтральная, сумма цветом своего типа ($mode)', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          type: TransactionType.expense,
          total: Stream.value(Money.fromMinor(1234500, 'RUB')),
          mode: mode,
        ),
      );
      await tester.pump();
      final context = tester.element(find.byType(MonthSummaryCard));
      final colors = context.appColors;
      final scheme = Theme.of(context).colorScheme;

      final caption = find.text('Расходы за сентябрь');
      expect(
        _colorOf(tester, caption),
        scheme.onSurfaceVariant,
        reason: 'подпись расхода',
      );
      expect(
        _colorOf(tester, find.text('$_expenseSign$_money')),
        colors.expense,
      );

      await tester.pumpWidget(
        _app(
          type: TransactionType.income,
          total: Stream.value(Money.fromMinor(1234500, 'RUB')),
          mode: mode,
        ),
      );
      await tester.pump();
      expect(
        _colorOf(tester, find.text('Доходы за сентябрь')),
        scheme.onSurfaceVariant,
        reason: 'подпись дохода',
      );
      expect(_colorOf(tester, find.text('+$_money')), colors.income);
    });

    testWidgets('подпись и «Пока нет» читаемы на фоне карточки ($mode)', (
      tester,
    ) async {
      for (final type in TransactionType.values) {
        await tester.pumpWidget(
          _app(type: type, total: Stream.value(Money.zero('RUB')), mode: mode),
        );
        await tester.pump();
        final context = tester.element(find.byType(MonthSummaryCard));
        final scheme = Theme.of(context).colorScheme;
        // Обе карточки без заливки: фон у них surface.
        expect(
          contrastRatio(scheme.onSurfaceVariant, scheme.surface),
          greaterThanOrEqualTo(4.5),
          reason: '$type, $mode',
        );
      }
    });
  }

  testWidgets('ошибка: иконка цветом error, текст нейтральный', (tester) async {
    await tester.pumpWidget(
      _app(
        type: TransactionType.expense,
        total: Stream.error(StateError('boom')),
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
    expect(tester.takeException(), isNull);
  });

  testWidgets('скринридер: сумма прописью, без знака и символа валюты', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(type: TransactionType.expense, total: Stream.value(_spoken)),
    );
    await tester.pump();

    expect(
      find.bySemanticsLabel('Расходы за сентябрь: 12345 рублей 50 копеек'),
      findsOneWidget,
    );
    // Знак «минус» в подписи для скринридера не появляется.
    expect(find.bySemanticsLabel(RegExp(_expenseSign)), findsNothing);
    semantics.dispose();
  });

  testWidgets('шрифт 200% на узком экране, все состояния: без переполнения', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(240, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Поток однократный: для каждого прогона создаём свой.
    final states = <Stream<Money> Function()>[
      () => Stream.value(Money.fromMinor(987654321, 'RUB')),
      () => Stream.value(Money.zero('RUB')),
      () => Stream.error(StateError('boom')),
    ];
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      for (final type in TransactionType.values) {
        for (final total in states) {
          await tester.pumpWidget(
            _app(type: type, total: total(), mode: mode, textScale: 2),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$type, $mode');
        }
      }
    }
  });

  testWidgets('карточка меняет данные потока без пересоздания виджета', (
    tester,
  ) async {
    final controller = StreamController<Money>();
    addTearDown(controller.close);
    await tester.pumpWidget(
      _app(type: TransactionType.income, total: controller.stream),
    );
    await tester.pump();
    // До первого значения ни подписи, ни «Пока нет».
    expect(find.text('Пока нет'), findsNothing);
    expect(find.textContaining('Доходы за'), findsNothing);

    controller.add(Money.zero('RUB'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Пока нет'), findsOneWidget);
  });
}
