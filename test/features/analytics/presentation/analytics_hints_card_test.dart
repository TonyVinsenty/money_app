import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/format/money_format.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/core/ui/theme/app_theme.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/domain/hints.dart';
import 'package:money_app/features/analytics/presentation/analytics_hints_card.dart';
import 'package:money_app/features/analytics/presentation/analytics_texts.dart';
import 'package:money_app/features/categories/domain/category.dart';
import 'package:money_app/features/categories/domain/category_kind.dart';
import 'package:money_app/features/transactions/domain/transaction.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

// 12 октября 2026 - понедельник.
final _today = DateOnly(2026, 10, 12);
final _nbsp = String.fromCharCode(0x00A0);
final _dash = String.fromCharCode(0x2014);
final _en = String.fromCharCode(0x2013);

Category _category(String id, String name) => Category.topLevel(
  id: id,
  kind: CategoryKind.expense,
  name: name,
  iconKey: 'icon',
  sortOrder: 0,
);

final _cafe = _category('cafe', 'Кафе');
final _food = _category('food', 'Продукты');

Transaction _tx(String id, int minor, DateOnly day, String category) =>
    Transaction(
      id: id,
      type: TransactionType.expense,
      amount: Money.fromMinor(minor, 'RUB'),
      occurredOn: day,
      occurredAt: DateTime.utc(day.year, day.month, day.day, 9),
      categoryId: category,
    );

String _money(int minor) => formatMoney(Money.fromMinor(minor, 'RUB'));

final _october = currentPeriod(PeriodKind.month, _today);

/// Правило 1: кафе в сентябре 6 500, в октябре уже 8 000.
List<Transaction> _rule1() => [
  _tx('s', 650000, DateOnly(2026, 9, 19), 'cafe'),
  _tx('o', 800000, DateOnly(2026, 10, 10), 'cafe'),
];

/// Правило 2: средний чек продуктов 100 -> 118 (пять операций в обоих периодах).
List<Transaction> _rule2() => [
  for (var i = 1; i <= 5; i++) ...[
    _tx('p$i', 10000, DateOnly(2026, 9, i), 'food'),
    _tx('c$i', 11800, DateOnly(2026, 10, i), 'food'),
  ],
];

Future<void> _pump(
  WidgetTester tester,
  List<Transaction> transactions, {
  AnalyticsPeriod? period,
  double textScale = 1,
  double width = 360,
}) async {
  tester.view.physicalSize = Size(width, 900);
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
        body: SingleChildScrollView(
          child: AnalyticsHintsCard(
            transactions: transactions,
            period: period ?? _october,
            today: _today,
            categories: [_cafe, _food],
            currency: 'RUB',
          ),
        ),
      ),
    ),
  );
}

String _name(String id) => id == 'cafe' ? 'Кафе' : 'Продукты';

String _above(AnalyticsPeriod period, DateOnly today, {bool spoken = false}) =>
    analyticsHintText(
      CategoryAbovePreviousHint(
        categoryId: 'cafe',
        current: Money.fromMinor(800000, 'RUB'),
        previousTotal: Money.fromMinor(650000, 'RUB'),
      ),
      nameOf: _name,
      period: period,
      today: today,
      spoken: spoken,
    );

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  group('тексты', () {
    test('правило 1: месяц', () {
      expect(
        _above(_october, _today),
        'Кафе: уже потрачено ${_money(800000)} $_dash больше, чем за весь сентябрь '
        '(${_money(650000)})',
      );
    });

    test('правило 1: месяц прошлого года — с годом', () {
      final today = DateOnly(2026, 1, 5);
      expect(
        _above(currentPeriod(PeriodKind.month, today), today),
        contains('за весь декабрь 2025 ('),
      );
    });

    test('правило 1: неделя, год, день', () {
      expect(
        _above(currentPeriod(PeriodKind.week, _today), _today),
        contains('больше, чем за всю прошлую неделю ('),
      );
      expect(
        _above(currentPeriod(PeriodKind.year, _today), _today),
        contains('больше, чем за весь 2025 год ('),
      );
      expect(
        _above(currentPeriod(PeriodKind.day, _today), _today),
        contains('больше, чем вчера за весь день ('),
      );
    });

    test('правило 1: свой интервал — склонение «дней»', () {
      expect(
        _above(
          customPeriod(DateOnly(2026, 10, 3), _today, today: _today),
          _today,
        ),
        contains('больше, чем за предыдущие 10 дней ('),
      );
      expect(
        _above(
          customPeriod(DateOnly(2026, 9, 22), _today, today: _today),
          _today,
        ),
        contains('за предыдущие 21 день ('),
      );
      expect(
        _above(
          customPeriod(DateOnly(2026, 10, 9), _today, today: _today),
          _today,
        ),
        contains('за предыдущие 4 дня ('),
      );
    });

    test('правило 2: больше и меньше, хвост как в «Сравнении»', () {
      String text(int percent, AnalyticsPeriod period) => analyticsHintText(
        AverageCheckChangeHint(
          categoryId: 'food',
          currentAverage: Money.fromMinor(11800, 'RUB'),
          previousAverage: Money.fromMinor(10000, 'RUB'),
          percent: percent,
        ),
        nameOf: _name,
        period: period,
        today: _today,
      );
      expect(
        text(18, _october),
        'Продукты: средний чек на 18$_nbsp% больше, чем 1${_en}12 сентября',
      );
      expect(
        text(-20, _october),
        'Продукты: средний чек на 20$_nbsp% меньше, чем 1${_en}12 сентября',
      );
      expect(
        text(18, currentPeriod(PeriodKind.day, _today)),
        endsWith(', чем вчера'),
      );
      expect(
        text(18, currentPeriod(PeriodKind.year, _today)),
        endsWith(', чем 1 января $_en 12 октября 2025'),
      );
    });

    test('правило 3: все дни недели в дательном падеже', () {
      const days = [
        'понедельникам',
        'вторникам',
        'средам',
        'четвергам',
        'пятницам',
        'субботам',
        'воскресеньям',
      ];
      for (var i = 0; i < 7; i++) {
        expect(
          analyticsHintText(
            BusiestWeekdayHint(
              weekday: i + 1,
              sharePercent: 28,
              amount: Money.fromMinor(100, 'RUB'),
            ),
            nameOf: _name,
            period: _october,
            today: _today,
          ),
          'Больше всего тратите по ${days[i]} $_dash 28$_nbsp% расходов',
        );
      }
    });

    test('озвучка: слова вместо знаков', () {
      expect(
        _above(_october, _today, spoken: true),
        'Кафе: уже потрачено 8000 рублей, больше, чем за весь сентябрь, 6500 рублей',
      );
      String weekday(int share) => analyticsHintText(
        BusiestWeekdayHint(
          weekday: 6,
          sharePercent: share,
          amount: Money.fromMinor(100, 'RUB'),
        ),
        nameOf: _name,
        period: _october,
        today: _today,
        spoken: true,
      );
      expect(
        weekday(28),
        'Больше всего тратите по субботам, 28 процентов расходов',
      );
      expect(weekday(31), contains('31 процент '));
      expect(weekday(33), contains('33 процента '));
    });
  });

  group('карточка', () {
    testWidgets('нет подсказок — карточки нет, места она не занимает', (
      tester,
    ) async {
      await _pump(tester, const []);

      expect(find.byKey(AnalyticsHintsCard.cardKey), findsNothing);
      expect(tester.getSize(find.byType(AnalyticsHintsCard)), Size.zero);
    });

    testWidgets('одна подсказка: лампочка и строка', (tester) async {
      await _pump(tester, _rule1());

      expect(find.byKey(AnalyticsHintsCard.cardKey), findsOneWidget);
      expect(find.byIcon(Icons.lightbulb_outline), findsOneWidget);
      expect(
        find.text(
          'Кафе: уже потрачено ${_money(800000)} $_dash больше, чем за весь сентябрь '
          '(${_money(650000)})',
        ),
        findsOneWidget,
      );
      expect(find.byKey(AnalyticsHintsCard.lineKey(1)), findsNothing);
    });

    testWidgets('три подсказки по порядку правил', (tester) async {
      await _pump(tester, [..._rule1(), ..._rule2()]);

      expect(
        tester.widget<Text>(find.byKey(AnalyticsHintsCard.lineKey(0))).data,
        startsWith('Кафе: уже потрачено '),
      );
      expect(
        tester.widget<Text>(find.byKey(AnalyticsHintsCard.lineKey(1))).data,
        'Продукты: средний чек на 18$_nbsp% больше, чем 1${_en}12 сентября',
      );
      expect(
        tester.widget<Text>(find.byKey(AnalyticsHintsCard.lineKey(2))).data,
        'Больше всего тратите по субботам $_dash 94$_nbsp% расходов',
      );
      expect(find.byKey(AnalyticsHintsCard.lineKey(3)), findsNothing);
    });

    testWidgets('прошедший период: правила 1 нет, остаётся правило 3', (
      tester,
    ) async {
      final september = currentPeriod(PeriodKind.month, DateOnly(2026, 9, 15));
      // Август 6 500, сентябрь 8 000: «уже» про прошедший месяц не говорят.
      await _pump(tester, [
        _tx('a', 650000, DateOnly(2026, 8, 19), 'cafe'),
        _tx('s', 800000, DateOnly(2026, 9, 10), 'cafe'),
      ], period: september);

      expect(find.byKey(AnalyticsHintsCard.lineKey(0)), findsOneWidget);
      expect(find.byKey(AnalyticsHintsCard.lineKey(1)), findsNothing);
      expect(find.textContaining('уже'), findsNothing);
    });

    testWidgets('«Без категории» и архивная категория в имени', (tester) async {
      final archived = _category(
        'old',
        'Старая',
      ).archived(DateTime.utc(2026, 9, 1));
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AnalyticsHintsCard(
                transactions: [
                  _tx('a', 650000, DateOnly(2026, 9, 19), 'old'),
                  _tx('b', 800000, DateOnly(2026, 10, 10), 'old'),
                  _tx('c', 640000, DateOnly(2026, 9, 19), 'ghost'),
                  _tx('d', 700000, DateOnly(2026, 10, 10), 'ghost'),
                ],
                period: _october,
                today: _today,
                categories: [archived],
                currency: 'RUB',
              ),
            ),
          ),
        ),
      );

      expect(find.textContaining('Старая: уже потрачено '), findsOneWidget);
      expect(
        find.textContaining('Без категории: уже потрачено '),
        findsOneWidget,
      );
    });

    testWidgets(
      'озвучка: заголовок на всю карточку, строки отдельными узлами',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pump(tester, _rule1());

        expect(find.bySemanticsLabel('Подсказки по расходам'), findsOneWidget);
        expect(
          find.bySemanticsLabel(
            'Кафе: уже потрачено 8000 рублей, больше, чем за весь сентябрь, '
            '6500 рублей',
          ),
          findsOneWidget,
        );
        handle.dispose();
      },
    );

    testWidgets('360 dp и 200 %: без переполнения', (tester) async {
      await _pump(tester, [..._rule1(), ..._rule2()], textScale: 2, width: 360);

      expect(tester.takeException(), isNull);
      expect(find.byKey(AnalyticsHintsCard.lineKey(2)), findsOneWidget);
    });
  });
}
