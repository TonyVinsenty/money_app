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
import 'package:money_app/features/analytics/presentation/analytics_screen.dart';
import 'package:money_app/features/analytics/presentation/period_summary_card.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

import '../../../support/fixture_transactions.dart';

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
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
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

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  testWidgets('чипы видов и подпись месяца', (tester) async {
    await _pump(tester);

    for (final label in ['День', 'Неделя', 'Месяц', 'Год']) {
      expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
    }
    expect(find.widgetWithText(ChoiceChip, 'Свой'), findsOneWidget);
    expect(find.text('Октябрь 2026'), findsOneWidget);
  });

  testWidgets('выбранный чип отмечен «выбрано» для скринридера', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, kind: PeriodKind.week);

    expect(
      tester.getSemantics(find.widgetWithText(ChoiceChip, 'Неделя')),
      isSemantics(isSelected: true),
    );
    expect(
      tester.getSemantics(find.widgetWithText(ChoiceChip, 'Месяц')),
      isSemantics(isSelected: false),
    );
    handle.dispose();
  });

  testWidgets('нажатие чипа зовёт колбэк с видом', (tester) async {
    final calls = <PeriodKind>[];
    await _pump(tester, onKindSelected: calls.add);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Год'));

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

    expect(find.text('28 сентября \u2013 4 октября'), findsOneWidget);
  });

  testWidgets('стрелки не меньше 48 dp', (tester) async {
    await _pump(tester, onPrevious: () {}, onNext: () {});

    for (final key in [PeriodSwitcher.previousKey, PeriodSwitcher.nextKey]) {
      final size = tester.getSize(find.byKey(key));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('шрифт 200% на 360 dp: чипы переносятся, без переполнения', (
    tester,
  ) async {
    await _pump(tester, textScale: 2, onPrevious: () {}, onNext: () {});

    expect(tester.takeException(), isNull);
    final tops = {
      for (final label in ['День', 'Неделя', 'Месяц', 'Год'])
        tester.getTopLeft(find.widgetWithText(ChoiceChip, label)).dy,
    };
    expect(tops.length, greaterThan(1));
    expect(find.text('Октябрь 2026'), findsOneWidget);
  });

  testWidgets('шрифт 100% на 360 dp: пять чипов в одну строку, без галочки', (
    tester,
  ) async {
    // В тестах нет настоящего шрифта: вместо него квадратные буквы шириной в
    // целый кегль, вдвое шире Roboto. Масштаб 0.55 даёт ширину слов, как у
    // Roboto при шрифте 100%.
    await _pump(tester, textScale: 0.55, onCustom: (_, _) {});

    expect(tester.takeException(), isNull);
    final tops = {
      for (final label in ['День', 'Неделя', 'Месяц', 'Год', 'Свой'])
        tester.getTopLeft(find.widgetWithText(ChoiceChip, label)).dy,
    };
    expect(tops.length, 1);
    for (final chip in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip))) {
      expect(chip.showCheckmark, isFalse);
    }
  });

  testWidgets('чипы периода проходят проверку зоны нажатия', (tester) async {
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

    Stream<PeriodTransactions> data(List<Transaction> list) =>
        Stream.value((range: september, transactions: list));

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

      controller.add((range: september, transactions: const []));
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

    testWidgets('чип «Свой» пятый; без выбора интервала не выбран', (
      tester,
    ) async {
      await _pump(tester, onCustom: (_, _) {});

      final labels = [
        for (final chip in tester.widgetList<ChoiceChip>(
          find.byType(ChoiceChip),
        ))
          (chip.label as Text).data,
      ];
      expect(labels, ['День', 'Неделя', 'Месяц', 'Год', 'Свой']);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Свой'))
            .selected,
        isFalse,
      );
    });

    testWidgets('для своего интервала чип отмечен выбранным', (tester) async {
      await _pump(tester, period: custom, onCustom: (_, _) {});

      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Свой'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Месяц'))
            .selected,
        isFalse,
      );
    });

    testWidgets('нажатие открывает диалог: последний день — сегодня, первый — '
        'день первой операции', (tester) async {
      await _pump(tester, firstDay: DateOnly(2026, 9, 10), onCustom: (_, _) {});

      await tester.tap(find.widgetWithText(ChoiceChip, 'Свой'));
      await tester.pumpAndSettle();

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

      await tester.tap(find.widgetWithText(ChoiceChip, 'Свой'));
      await tester.pumpAndSettle();

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

        await tester.tap(find.widgetWithText(ChoiceChip, 'Свой'));
        await tester.pumpAndSettle();

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

      await tester.tap(find.widgetWithText(ChoiceChip, 'Свой'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(calls, isEmpty);
      expect(find.byType(DateRangePickerDialog), findsNothing);
    });

    testWidgets('шрифт 200% на 360 dp: пять чипов без переполнения', (
      tester,
    ) async {
      await _pump(tester, textScale: 2, period: custom, onCustom: (_, _) {});

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(ChoiceChip, 'Свой'), findsOneWidget);
    });
  });
}
