import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/format/money_spoken.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/period_switcher.dart';
import 'package:money_app/core/ui/theme/app_colors.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/domain/period_summary.dart';
import 'package:money_app/features/analytics/presentation/analytics_controller.dart';
import 'package:money_app/features/analytics/presentation/analytics_screen.dart';
import 'package:money_app/features/analytics/presentation/period_header.dart';
import 'package:money_app/features/analytics/presentation/period_summary_card.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/fixture_transactions.dart';
import '../../../support/nbsp.dart';

final _today = DateOnly(2026, 10, 4);

Future<void> _pump(
  WidgetTester tester, {
  PeriodKind kind = PeriodKind.month,
  ValueChanged<PeriodKind>? onKindSelected,
  VoidCallback? onPrevious,
  VoidCallback? onNext,
  Stream<PeriodTransactions>? transactions,
  double textScale = 1,
  AnalyticsPeriod? period,
  DateOnly? firstDay,
  bool firstDayKnown = false,
  void Function(DateOnly, DateOnly)? onCustom,
  AnalyticsSection section = AnalyticsSection.categories,
  ValueChanged<AnalyticsSection>? onSection,
  double width = 360,
  double? tabFontSize,
  VoidCallback? onAddExpense,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: tabFontSize == null
          ? AppTheme.light()
          : AppTheme.light().copyWith(
              tabBarTheme: TabBarThemeData(
                labelStyle: TextStyle(fontSize: tabFontSize),
              ),
            ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: AnalyticsScreen(
          period: period ?? currentPeriod(kind, _today),
          firstDay: firstDay,
          firstDayKnown: firstDayKnown,
          onCustomRangeSelected: onCustom,
          section: section,
          onSectionSelected: onSection,
          onAddExpense: onAddExpense,
          today: _today,
          onKindSelected: onKindSelected ?? (_) {},
          onPrevious: onPrevious,
          onNext: onNext,
          transactions: transactions ?? const Stream.empty(),
          categories: Stream.value(const <Category>[]),
        ),
      ),
    ),
  );
}

Finder _kindButtonText(String text) => find.descendant(
  of: find.byKey(PeriodHeader.kindButtonKey),
  matching: find.text(text),
);

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(PeriodHeader.kindButtonKey));
  await tester.pumpAndSettle();
}

Future<void> _pickItem(WidgetTester tester, Finder item) async {
  await _openMenu(tester);
  await tester.tap(item);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('кнопка вида, пункты меню и подпись месяца', (tester) async {
    await _pump(tester);

    expect(_kindButtonText('Месяц'), findsOneWidget);
    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.text('Октябрь 2026'), findsOneWidget);

    await _openMenu(tester);
    for (final label in ['День', 'Неделя', 'Месяц', 'Год', 'Свой период…']) {
      expect(find.widgetWithText(MenuItemButton, label), findsOneWidget);
    }
  });

  group('строка разделов', () {
    Stream<PeriodTransactions> someData() => Stream.value((
      range: monthRange(DateOnly(2026, 10, 1)),
      previousRange: monthRange(DateOnly(2026, 9, 1)),
      transactions: [
        Transaction(
          id: 'a',
          type: TransactionType.expense,
          amount: Money.fromMinor(100, 'RUB'),
          occurredOn: DateOnly(2026, 10, 2),
          occurredAt: DateTime.utc(2026, 10, 2, 9),
          categoryId: 'food',
        ),
      ],
    ));

    testWidgets(
      'по умолчанию «Категории»: четыре раздела и прежнее содержимое',
      (tester) async {
        await _pump(tester, transactions: someData());
        await tester.pump();

        expect(find.byType(Tab), findsNWidgets(4));
        expect(find.widgetWithText(Tab, 'Категории'), findsOneWidget);
        expect(find.widgetWithText(Tab, 'Динамика'), findsOneWidget);
        expect(find.widgetWithText(Tab, 'Сравнение'), findsOneWidget);
        expect(find.widgetWithText(Tab, 'Операции'), findsOneWidget);
        expect(find.byType(PeriodSummaryCard), findsOneWidget);
        expect(find.byKey(analyticsComparisonKey), findsNothing);
      },
    );

    testWidgets('раздел «Динамика»: график, период на месте, вкладка 1', (
      tester,
    ) async {
      await _pump(
        tester,
        transactions: someData(),
        section: AnalyticsSection.dynamics,
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(analyticsDynamicsKey), findsOneWidget);
      expect(find.byType(PeriodSummaryCard), findsNothing);
      expect(find.text('Октябрь 2026'), findsOneWidget);
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 1);
    });

    testWidgets('касание «Сравнение» зовёт колбэк с разделом', (tester) async {
      final calls = <AnalyticsSection>[];
      await _pump(tester, transactions: someData(), onSection: calls.add);
      await tester.pump();

      await tester.ensureVisible(find.widgetWithText(Tab, 'Сравнение'));
      await tester.tap(find.widgetWithText(Tab, 'Сравнение'));
      await tester.pump();

      expect(calls, [AnalyticsSection.comparison]);
    });

    testWidgets('раздел «Сравнение»: содержимое другое, период на месте', (
      tester,
    ) async {
      await _pump(
        tester,
        transactions: someData(),
        section: AnalyticsSection.comparison,
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(analyticsComparisonKey), findsOneWidget);
      expect(find.byType(PeriodSummaryCard), findsNothing);
      expect(find.text('Октябрь 2026'), findsOneWidget);
      expect(_kindButtonText('Месяц'), findsOneWidget);
      expect(tester.widget<TabBar>(find.byType(TabBar)).controller!.index, 2);
    });

    testWidgets('свайпа между разделами нет: нет TabBarView', (tester) async {
      await _pump(tester, transactions: someData());
      await tester.pump();

      expect(find.byType(TabBarView), findsNothing);
    });

    testWidgets('шрифт 200% на 360 dp: строка прокручивается, без '
        'переполнения', (tester) async {
      await _pump(tester, textScale: 2, transactions: someData());
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(tester.widget<TabBar>(find.byType(TabBar)).isScrollable, isTrue);
      await tester.drag(find.byType(TabBar), const Offset(-300, 0));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(Tab, 'Сравнение'), findsOneWidget);
    });

    testWidgets('скринридер: вкладка с названием и номером', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, transactions: someData());
      await tester.pump();

      await tester.ensureVisible(find.widgetWithText(Tab, 'Сравнение'));
      await tester.pump();
      final label = tester
          .getSemantics(find.widgetWithText(Tab, 'Сравнение'))
          .label;
      expect(label, contains('Сравнение'));
      expect(label, contains('3'));
      handle.dispose();
    });

    for (final width in [360.0, 411.0]) {
      testWidgets('${width.toInt()} dp, 100 %: четыре раздела поровну', (
        tester,
      ) async {
        // В тестах шрифт Ahem шире настоящего (квадрат на букву), поэтому размер
        // уменьшен так, чтобы ширина совпала с живым Roboto 14 sp (~72 dp).
        await _pump(
          tester,
          width: width,
          tabFontSize: 8,
          transactions: someData(),
        );
        await tester.pump();

        final barRect = tester.getRect(find.byKey(analyticsSectionBarKey));
        final bar = barRect.size;
        expect(find.byType(Tab), findsNWidgets(4));
        final titles = ['Категории', 'Динамика', 'Сравнение', 'Операции'];
        for (var i = 0; i < titles.length; i++) {
          final title = titles[i];
          final tab = find.widgetWithText(Tab, title);
          // Ячейки равной ширины: центр i-го раздела в середине i-й четверти.
          expect(
            tester.getCenter(tab).dx,
            closeTo(barRect.left + bar.width * (i + 0.5) / 4, 0.5),
          );
          expect(tester.getRect(tab).right, lessThanOrEqualTo(width));
          // Текст не обрезан: его ширина помещается в ячейку.
          expect(
            tester.getSize(find.text(title)).width,
            lessThan(bar.width / 4),
          );
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('200 %: строка прокручивается, выбранный раздел виден', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        textScale: 2,
        section: AnalyticsSection.operations,
        transactions: someData(),
      );
      await tester.pump();

      final scrollable = find.descendant(
        of: find.byKey(analyticsSectionBarKey),
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsOneWidget);
      final tab = find.widgetWithText(Tab, 'Операции');
      await tester.ensureVisible(tab);
      await tester.pump();
      expect(tester.getRect(tab).right, lessThanOrEqualTo(360));
      // Между соседними подписями есть зазор.
      final titles = ['Категории', 'Динамика', 'Сравнение', 'Операции'];
      for (var i = 0; i < titles.length - 1; i++) {
        final left = tester.getRect(find.text(titles[i])).right;
        final right = tester.getRect(find.text(titles[i + 1])).left;
        expect(right - left, greaterThanOrEqualTo(16));
      }
      expect(tester.getSemantics(tab).label, contains('4'));
      handle.dispose();
    });
  });

  testWidgets('кнопка вида озвучена, текущий пункт меню отмечен', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, kind: PeriodKind.week);

    expect(
      tester.getSemantics(find.byKey(PeriodHeader.kindButtonKey)).label,
      contains('Период: неделя, изменить'),
    );
    await _openMenu(tester);
    expect(
      find.descendant(
        of: find.byKey(PeriodHeader.itemKey(PeriodKind.week)),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.check), findsOneWidget);
    handle.dispose();
  });

  testWidgets('выбор пункта меню зовёт колбэк с видом', (tester) async {
    final calls = <PeriodKind>[];
    await _pump(tester, onKindSelected: calls.add);

    await _pickItem(tester, find.byKey(PeriodHeader.itemKey(PeriodKind.year)));

    expect(calls, [PeriodKind.year]);
  });

  testWidgets('стрелка «вперёд» без колбэка недоступна и озвучена', (
    tester,
  ) async {
    var previous = 0;
    await _pump(tester, onPrevious: () => previous++);

    final next = tester.widget<IconButton>(find.byKey(PeriodSwitcher.nextKey));
    expect(next.onPressed, isNull);
    expect(next.tooltip, 'Следующий месяц');
    expect(find.byTooltip('Следующий месяц'), findsOneWidget);

    await tester.tap(find.byKey(PeriodSwitcher.previousKey));
    expect(previous, 1);
  });

  testWidgets('подсказки стрелок меняются с видом', (tester) async {
    const expected = {
      PeriodKind.day: ('Предыдущий день', 'Следующий день'),
      PeriodKind.week: ('Предыдущая неделя', 'Следующая неделя'),
      PeriodKind.month: ('Предыдущий месяц', 'Следующий месяц'),
      PeriodKind.year: ('Предыдущий год', 'Следующий год'),
    };
    for (final entry in expected.entries) {
      await _pump(tester, kind: entry.key, onPrevious: () {}, onNext: () {});
      expect(find.byTooltip(entry.value.$1), findsOneWidget);
      expect(find.byTooltip(entry.value.$2), findsOneWidget);
    }
  });

  testWidgets('подпись недели в стиле «Главной»', (tester) async {
    await _pump(tester, kind: PeriodKind.week);

    expect(
      find.text('28$dateNbspсентября \u2013 4$dateNbspоктября'),
      findsOneWidget,
    );
  });

  testWidgets('стрелки не меньше 48 dp', (tester) async {
    await _pump(tester, onPrevious: () {}, onNext: () {});

    for (final key in [PeriodSwitcher.previousKey, PeriodSwitcher.nextKey]) {
      final size = tester.getSize(find.byKey(key));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('шрифт 200% на 360 dp: вид над стрелками, без переполнения', (
    tester,
  ) async {
    await _pump(tester, textScale: 2, onPrevious: () {}, onNext: () {});

    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.byKey(PeriodHeader.kindButtonKey)).dy,
      lessThan(tester.getTopLeft(find.byKey(PeriodSwitcher.previousKey)).dy),
    );
    expect(find.text('Октябрь 2026'), findsOneWidget);
    await _openMenu(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('шрифт 100% на 360 dp: вид и стрелки в одной строке', (
    tester,
  ) async {
    await _pump(tester, onPrevious: () {}, onNext: () {});

    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.byKey(PeriodHeader.kindButtonKey)).dy,
      closeTo(tester.getTopLeft(find.byKey(PeriodSwitcher.previousKey)).dy, 8),
    );
  });

  testWidgets('шапка периода проходит проверку зоны нажатия', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, onCustom: (_, _) {});

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    handle.dispose();
  });

  testWidgets('карточка итогов: рамка 16 dp без заливки, как на «Главной»', (
    tester,
  ) async {
    await _pump(
      tester,
      transactions: Stream.value((
        range: monthRange(DateOnly(2026, 9, 1)),
        previousRange: monthRange(DateOnly(2026, 8, 1)),
        transactions: [
          Transaction(
            id: 'a',
            type: TransactionType.expense,
            amount: Money.fromMinor(100, 'RUB'),
            occurredOn: DateOnly(2026, 9, 5),
            occurredAt: DateTime.utc(2026, 9, 5, 9),
            categoryId: 'food',
          ),
        ],
      )),
    );
    await tester.pump();

    final card = tester.widget<Card>(
      find.descendant(
        of: find.byType(PeriodSummaryCard),
        matching: find.byType(Card),
      ),
    );
    final scheme = Theme.of(tester.element(find.byType(PeriodSummaryCard)))
        .colorScheme;
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(PeriodSummaryCard),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, scheme.surface);
    expect(material.elevation, 0);
    expect(card.margin, EdgeInsets.zero);
    final shape = card.shape! as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(16));
    expect(shape.side.color, scheme.outlineVariant);
  });

  group('итоги периода', () {
    final september = monthRange(DateOnly(2026, 9, 1));

    Transaction tx(TransactionType type, int minor, {int day = 5}) =>
        Transaction(
          id: '$type-$minor-$day',
          type: type,
          amount: Money.fromMinor(minor, 'RUB'),
          occurredOn: DateOnly(2026, 9, day),
          occurredAt: DateTime.utc(2026, 9, day, 9),
          categoryId: 'food',
        );

    Stream<PeriodTransactions> data(List<Transaction> list) => Stream.value((
      range: september,
      previousRange: monthRange(DateOnly(2026, 8, 1)),
      transactions: list,
    ));

    Money rub(int minor) => Money.fromMinor(minor, 'RUB');

    Color colorOf(WidgetTester tester, Key key) {
      final text = find.descendant(
        of: find.byKey(key),
        matching: find.byWidgetPredicate(
          (w) => w is Text && w.style?.color != null,
        ),
      );
      return tester.widget<Text>(text.last).style!.color!;
    }

    String textOf(WidgetTester tester, Key key) => tester
        .widget<Text>(
          find
              .descendant(of: find.byKey(key), matching: find.byType(Text))
              .last,
        )
        .data!;

    testWidgets('сентябрь тестового набора: суммы, знаки, цвета, число', (
      tester,
    ) async {
      final all = loadFixtureTransactions();
      await _pump(tester, transactions: data(all));
      await tester.pump();

      final summary = summarizePeriod(all, september, currency: 'RUB');
      expect(summary.expense, rub(12803388));
      expect(summary.income, rub(10294900));
      expect(
        textOf(tester, PeriodSummaryCard.expenseKey),
        '\u2212${formatMoney(rub(12803388))}',
      );
      expect(
        textOf(tester, PeriodSummaryCard.incomeKey),
        '+${formatMoney(rub(10294900))}',
      );
      expect(
        textOf(tester, PeriodSummaryCard.balanceKey),
        formatMoney(rub(-2508488)),
      );
      expect(
        textOf(tester, PeriodSummaryCard.balanceKey),
        startsWith('\u2212'),
      );
      expect(
        colorOf(tester, PeriodSummaryCard.expenseKey),
        AppColors.light.expense,
      );
      expect(
        colorOf(tester, PeriodSummaryCard.incomeKey),
        AppColors.light.income,
      );
      expect(
        colorOf(tester, PeriodSummaryCard.balanceKey),
        AppColors.light.expense,
      );
      expect(find.text('Операций: ${summary.count}'), findsOneWidget);
    });

    testWidgets('положительный баланс: «+» и цвет дохода', (tester) async {
      await _pump(
        tester,
        transactions: data([
          tx(TransactionType.income, 50000),
          tx(TransactionType.expense, 20000),
        ]),
      );
      await tester.pump();

      expect(
        textOf(tester, PeriodSummaryCard.balanceKey),
        '+${formatMoney(rub(30000))}',
      );
      expect(
        colorOf(tester, PeriodSummaryCard.balanceKey),
        AppColors.light.income,
      );
    });

    testWidgets('нулевой баланс: без знака и нейтральным цветом', (
      tester,
    ) async {
      await _pump(
        tester,
        transactions: data([
          tx(TransactionType.income, 1000),
          tx(TransactionType.expense, 1000),
        ]),
      );
      await tester.pump();

      expect(textOf(tester, PeriodSummaryCard.balanceKey), formatMoney(rub(0)));
      final scheme = Theme.of(tester.element(find.byType(PeriodSummaryCard)))
          .colorScheme;
      expect(colorOf(tester, PeriodSummaryCard.balanceKey), scheme.onSurface);
    });

    testWidgets('пустой период: текст, а не нули', (tester) async {
      await _pump(
        tester,
        firstDay: DateOnly(2026, 9, 1),
        transactions: data(const []),
      );
      await tester.pump();

      expect(find.text('За этот период операций нет'), findsOneWidget);
      expect(find.textContaining('Операций пока нет'), findsNothing);
      expect(find.byType(PeriodSummaryCard), findsNothing);
      expect(
        find.text('Выберите другой период стрелками вверху'),
        findsOneWidget,
      );
      expect(find.text('Добавить расход'), findsNothing);
      final icon = tester.widget<Icon>(find.byIcon(Icons.bar_chart_rounded));
      expect(icon.size, 48);
    });

    testWidgets('пустая база: кнопка «Добавить расход» зовёт быстрый ввод', (
      tester,
    ) async {
      var taps = 0;
      await _pump(
        tester,
        firstDayKnown: true,
        transactions: data(const []),
        onAddExpense: () => taps++,
      );
      await tester.pump();

      expect(
        find.text('Выберите другой период стрелками вверху'),
        findsNothing,
      );
      await tester.tap(find.text('Добавить расход'));
      expect(taps, 1);
    });

    testWidgets('операции периода сравнения не попадают в итоги и кольцо', (
      tester,
    ) async {
      final august = Transaction(
        id: 'aug',
        type: TransactionType.expense,
        amount: Money.fromMinor(500000, 'RUB'),
        occurredOn: DateOnly(2026, 8, 20),
        occurredAt: DateTime.utc(2026, 8, 20, 9),
        categoryId: 'food',
      );
      await _pump(
        tester,
        transactions: data([august, tx(TransactionType.expense, 1000)]),
      );
      await tester.pump();

      expect(find.text('Операций: 1'), findsOneWidget);
      expect(
        textOf(tester, PeriodSummaryCard.expenseKey),
        '−${formatMoney(rub(1000))}',
      );
      expect(find.textContaining(formatMoney(rub(501000))), findsNothing);
    });

    testWidgets('в периоде пусто, в сравнении нет: «За этот период '
        'операций нет»', (tester) async {
      final august = Transaction(
        id: 'aug',
        type: TransactionType.expense,
        amount: Money.fromMinor(500000, 'RUB'),
        occurredOn: DateOnly(2026, 8, 20),
        occurredAt: DateTime.utc(2026, 8, 20, 9),
        categoryId: 'food',
      );
      await _pump(
        tester,
        firstDay: DateOnly(2026, 8, 20),
        transactions: data([august]),
      );
      await tester.pump();

      expect(find.text('За этот период операций нет'), findsOneWidget);
      expect(find.byType(PeriodSummaryCard), findsNothing);
    });

    testWidgets('первая операция неизвестна: приглашения нет, прежний текст', (
      tester,
    ) async {
      await _pump(tester, transactions: data(const []));
      await tester.pump();

      expect(find.text('За этот период операций нет'), findsOneWidget);
      expect(find.textContaining('Операций пока нет'), findsNothing);
    });

    testWidgets('операций нет вообще (известно): приглашение добавить', (
      tester,
    ) async {
      await _pump(tester, firstDayKnown: true, transactions: data(const []));
      await tester.pump();

      expect(
        find.text(
          'Операций пока нет. Добавьте первую — и здесь появится статистика',
        ),
        findsOneWidget,
      );
      expect(find.text('За этот период операций нет'), findsNothing);
    });

    testWidgets('операции только с нулевой суммой: карточка с нулями', (
      tester,
    ) async {
      await _pump(tester, transactions: data([tx(TransactionType.expense, 0)]));
      await tester.pump();

      expect(find.byType(PeriodSummaryCard), findsOneWidget);
      expect(find.text('За этот период операций нет'), findsNothing);
      expect(find.text('Операций: 1'), findsOneWidget);
    });

    testWidgets('до первого ответа виден скелетон', (tester) async {
      final controller = StreamController<PeriodTransactions>();
      addTearDown(controller.close);
      await _pump(tester, transactions: controller.stream);

      expect(find.byKey(analyticsSkeletonKey), findsOneWidget);
      expect(find.text('За этот период операций нет'), findsNothing);
      expect(find.byType(PeriodSummaryCard), findsNothing);

      controller.add((
        range: september,
        previousRange: monthRange(DateOnly(2026, 8, 1)),
        transactions: const [],
      ));
      await tester.pump();

      expect(find.byKey(analyticsSkeletonKey), findsNothing);
    });

    testWidgets('смена периода: до ответа остаются прежние итоги', (
      tester,
    ) async {
      await _pump(
        tester,
        transactions: data([tx(TransactionType.expense, 1000)]),
      );
      await tester.pump();
      expect(find.byType(PeriodSummaryCard), findsOneWidget);

      final next = StreamController<PeriodTransactions>();
      addTearDown(next.close);
      await _pump(tester, kind: PeriodKind.week, transactions: next.stream);

      expect(find.byType(PeriodSummaryCard), findsOneWidget);
      expect(find.text('За этот период операций нет'), findsNothing);
      expect(find.byKey(analyticsSkeletonKey), findsNothing);
      expect(
        textOf(tester, PeriodSummaryCard.expenseKey),
        '\u2212${formatMoney(rub(1000))}',
      );
    });

    testWidgets('ошибка потока: понятный текст', (tester) async {
      await _pump(tester, transactions: Stream.error(StateError('boom')));
      await tester.pump();

      expect(find.text('Не удалось посчитать итоги за период'), findsOneWidget);
    });

    testWidgets('скринридер читает суммы словами, по одному узлу на строку', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        transactions: data([
          tx(TransactionType.income, 50000),
          tx(TransactionType.expense, 128033),
        ]),
      );
      await tester.pump();

      expect(
        find.bySemanticsLabel('Расходы, минус ${spokenMoney(rub(128033))}'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Доходы, плюс ${spokenMoney(rub(50000))}'),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Баланс, ${spokenMoney(rub(-78033))}'),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('шрифт 200% на 360 dp: без переполнения', (tester) async {
      await _pump(
        tester,
        textScale: 2,
        transactions: data(loadFixtureTransactions()),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(PeriodSummaryCard), findsOneWidget);
    });
  });

  group('свой интервал', () {
    final custom = customPeriod(
      DateOnly(2026, 9, 1),
      DateOnly(2026, 9, 15),
      today: _today,
    );

    final customItem = find.byKey(PeriodHeader.customItemKey);

    testWidgets('пункт «Свой период…» последний; без выбора не отмечен', (
      tester,
    ) async {
      await _pump(tester, onCustom: (_, _) {});
      await _openMenu(tester);

      final labels = [
        for (final item in tester.widgetList<MenuItemButton>(
          find.byType(MenuItemButton),
        ))
          (item.child! as Text).data,
      ];
      expect(labels, ['День', 'Неделя', 'Месяц', 'Год', 'Свой период…']);
      expect(
        find.descendant(of: customItem, matching: find.byIcon(Icons.check)),
        findsNothing,
      );
    });

    testWidgets('без колбэка пункт «Свой период…» недоступен', (tester) async {
      await _pump(tester);
      await _openMenu(tester);

      expect(tester.widget<MenuItemButton>(customItem).onPressed, isNull);
    });

    testWidgets('для своего интервала пункт отмечен, кнопка «Свой период»', (
      tester,
    ) async {
      await _pump(tester, period: custom, onCustom: (_, _) {});

      expect(_kindButtonText('Свой период'), findsOneWidget);
      await _openMenu(tester);
      expect(
        find.descendant(of: customItem, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('нажатие открывает диалог: последний день — сегодня, первый — '
        'день первой операции', (tester) async {
      await _pump(tester, firstDay: DateOnly(2026, 9, 10), onCustom: (_, _) {});

      await _pickItem(tester, customItem);

      final dialog = tester.widget<DateRangePickerDialog>(
        find.byType(DateRangePickerDialog),
      );
      expect(dialog.lastDate, DateTime(2026, 10, 4));
      expect(dialog.firstDate, DateTime(2026, 9, 10));
      // Выбран октябрь с 1-го по 4-е (в границах).
      expect(
        dialog.initialDateRange,
        DateTimeRange(start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 4)),
      );
    });

    testWidgets('без операций первый день — сегодня', (tester) async {
      await _pump(tester, onCustom: (_, _) {});

      await _pickItem(tester, customItem);

      final dialog = tester.widget<DateRangePickerDialog>(
        find.byType(DateRangePickerDialog),
      );
      expect(dialog.firstDate, DateTime(2026, 10, 4));
      expect(dialog.initialDateRange!.start, DateTime(2026, 10, 4));
    });

    testWidgets(
      'повторное нажатие при выбранном «Свой» тоже открывает диалог',
      (tester) async {
        await _pump(
          tester,
          period: custom,
          firstDay: DateOnly(2026, 9, 1),
          onCustom: (_, _) {},
        );

        await _pickItem(tester, customItem);

        expect(find.byType(DateRangePickerDialog), findsOneWidget);
        expect(
          tester
              .widget<DateRangePickerDialog>(find.byType(DateRangePickerDialog))
              .initialDateRange,
          DateTimeRange(
            start: DateTime(2026, 9, 1),
            end: DateTime(2026, 9, 15),
          ),
        );
      },
    );

    testWidgets('отмена не зовёт колбэк', (tester) async {
      final calls = <(DateOnly, DateOnly)>[];
      await _pump(
        tester,
        firstDay: DateOnly(2026, 9, 1),
        onCustom: (s, e) => calls.add((s, e)),
      );

      await _pickItem(tester, customItem);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(calls, isEmpty);
      expect(find.byType(DateRangePickerDialog), findsNothing);
    });

    testWidgets('шрифт 200% на 360 dp: «Свой период» без переполнения', (
      tester,
    ) async {
      await _pump(tester, textScale: 2, period: custom, onCustom: (_, _) {});

      expect(tester.takeException(), isNull);
      expect(_kindButtonText('Свой период'), findsOneWidget);
      await _openMenu(tester);
      expect(tester.takeException(), isNull);
    });
  });
}
