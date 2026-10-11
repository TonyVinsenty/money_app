import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/domain/buckets.dart';
import 'package:money_app/features/analytics/domain/period_comparison.dart';
import 'package:money_app/features/analytics/presentation/analytics_controller.dart';
import 'package:money_app/features/analytics/presentation/analytics_texts.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

final _today = DateOnly(2026, 10, 11);
final _nbsp = String.fromCharCode(0x00A0);
final _minus = String.fromCharCode(0x2212);

AmountChange _change(int now, int before) => AmountChange(
  current: Money.fromMinor(now, 'RUB'),
  previous: Money.fromMinor(before, 'RUB'),
);

void main() {
  setUpAll(() => initializeDateFormatting('ru'));

  test('Т1: названия разделов', () {
    expect(
      [for (final s in AnalyticsSection.values) analyticsSectionTitle(s)],
      ['Категории', 'Динамика', 'Сравнение', 'Операции'],
    );
  });

  group('comparisonPhrase', () {
    test('часть месяца того же года', () {
      expect(
        comparisonPhrase(
          DateRange(DateOnly(2026, 9, 1), DateOnly(2026, 9, 11)),
          _today,
        ),
        '1\u201311 сентября',
      );
    });

    test('целый месяц: «в августе»; другой год — с годом', () {
      expect(
        comparisonPhrase(monthRange(DateOnly(2026, 8, 1)), _today),
        'в августе',
      );
      expect(
        comparisonPhrase(monthRange(DateOnly(2025, 12, 1)), _today),
        'в декабре 2025',
      );
    });

    test('целый год и часть года', () {
      expect(
        comparisonPhrase(yearRange(DateOnly(2025, 1, 1)), _today),
        'в 2025 году',
      );
      expect(
        comparisonPhrase(
          DateRange(DateOnly(2025, 1, 1), DateOnly(2025, 10, 11)),
          _today,
        ),
        '1 января \u2013 11 октября 2025',
      );
    });

    test('вчера, другой день, один день прошлого года', () {
      expect(
        comparisonPhrase(dayRange(DateOnly(2026, 10, 10)), _today),
        'вчера',
      );
      expect(
        comparisonPhrase(dayRange(DateOnly(2026, 10, 3)), _today),
        '3 октября',
      );
      expect(
        comparisonPhrase(dayRange(DateOnly(2025, 10, 3)), _today),
        '3 октября 2025',
      );
    });

    test('через границу месяцев и года', () {
      expect(
        comparisonPhrase(
          DateRange(DateOnly(2026, 9, 28), DateOnly(2026, 10, 4)),
          _today,
        ),
        '28 сентября \u2013 4 октября',
      );
      expect(
        comparisonPhrase(
          DateRange(DateOnly(2025, 12, 29), DateOnly(2026, 1, 4)),
          _today,
        ),
        '29 декабря 2025 \u2013 4 января 2026',
      );
    });
  });

  group('проценты', () {
    test('со знаком и неразрывным пробелом', () {
      expect(signedPercent(12), '+12$_nbsp%');
      expect(
        signedPercent(-4),
        '$_minus'
        '4$_nbsp%',
      );
      expect(signedPercent(0), '0$_nbsp%');
    });

    test('словами', () {
      expect(spokenSignedPercent(40), 'плюс 40 процентов');
      expect(spokenSignedPercent(-4), 'минус 4 процента');
      expect(spokenSignedPercent(-1), 'минус 1 процент');
      expect(spokenSignedPercent(0), '0 процентов');
    });
  });

  group('comparisonSummaryText', () {
    const expense = TransactionType.expense;

    test('больше, меньше, столько же', () {
      expect(
        comparisonSummaryText(_change(10000, 5000), expense, 'в августе'),
        'на 50,00$_nbsp₽ больше (+100$_nbsp%), чем в августе',
      );
      expect(
        comparisonSummaryText(_change(5000, 10000), expense, 'в августе'),
        'на 50,00$_nbsp₽ меньше ($_minus'
        '50$_nbsp%), чем в августе',
      );
      expect(
        comparisonSummaryText(_change(5000, 5000), expense, 'вчера'),
        'столько же, сколько вчера',
      );
    });

    test('процент округлился до нуля: «<1 %» и «меньше 1 процента»', () {
      final tiny = _change(100001, 100000);
      expect(
        comparisonSummaryText(tiny, expense, 'в августе'),
        'на 0,01$_nbsp₽ больше (<1$_nbsp%), чем в августе',
      );
      expect(
        comparisonSummaryText(tiny, expense, 'в августе', spoken: true),
        'на 0 рублей 1 копейка больше, меньше 1 процента, чем в августе',
      );
      expect(comparisonRowDelta(tiny), '↑ на 0,01$_nbsp₽ (<1$_nbsp%)');
    });

    test('большой процент с разделителем разрядов', () {
      expect(signedPercent(1420), '+1${_nbsp}420$_nbsp%');
      expect(comparisonRowDelta(_change(152000, 10000)), contains('+1'));
      expect(
        comparisonRowDelta(_change(152000, 10000)),
        endsWith('(+1${_nbsp}420$_nbsp%)'),
      );
    });

    test('озвучка исчезнувшей категории без повтора суммы', () {
      expect(
        comparisonRowSpoken('Кафе', _change(0, 300000)),
        'Кафе, 0 рублей, раньше было 3000 рублей, минус 100 процентов',
      );
    });

    test('озвучка итога: сумма словами', () {
      expect(
        comparisonTotalTitle(
          expense,
          Money.fromMinor(300000, 'RUB'),
          spoken: true,
        ),
        'Расходы: 3000 рублей',
      );
    });

    test('прошлое пусто: слово по типу, первая буква большая', () {
      expect(
        comparisonSummaryText(_change(5000, 0), expense, 'в августе'),
        'В августе расходов не было',
      );
      expect(
        comparisonSummaryText(
          _change(5000, 0),
          TransactionType.income,
          '1\u201311 сентября',
        ),
        '1\u201311 сентября доходов не было',
      );
    });
  });

  group('Т3: озвучка периода и категории в подписи графика', () {
    String spoken(AnalyticsPeriod p, {String? category}) => dynamicsChartSpoken(
      type: TransactionType.expense,
      period: p,
      step: BucketStep.day,
      buckets: const [],
      average: null,
      today: _today,
      categoryName: category,
    );

    test('неделя и свой интервал: «с ... по ...»', () {
      expect(
        spoken(currentPeriod(PeriodKind.week, _today)),
        'Расходы по дням с 5 по 11 октября',
      );
      expect(
        spoken(
          customPeriod(
            DateOnly(2026, 9, 28),
            DateOnly(2026, 10, 4),
            today: _today,
          ),
        ),
        'Расходы по дням с 28 сентября по 4 октября 2026',
      );
      expect(
        spoken(
          customPeriod(
            DateOnly(2025, 12, 15),
            DateOnly(2026, 2, 20),
            today: _today,
          ),
        ),
        'Расходы по дням с 15 декабря 2025 по 20 февраля 2026',
      );
      expect(
        spoken(currentPeriod(PeriodKind.week, DateOnly(2025, 11, 26))),
        'Расходы по дням с 24 по 30 ноября 2025',
      );
      expect(
        spoken(currentPeriod(PeriodKind.week, DateOnly(2026, 1, 1))),
        'Расходы по дням с 29 декабря 2025 по 4 января 2026',
      );
    });

    test('месяц, год, один день своего интервала', () {
      expect(
        spoken(currentPeriod(PeriodKind.month, _today)),
        'Расходы по дням за октябрь',
      );
      expect(
        spoken(currentPeriod(PeriodKind.year, _today)),
        'Расходы по дням за 2026 год',
      );
      expect(
        spoken(customPeriod(_today, _today, today: _today)),
        'Расходы по дням за 11 октября 2026',
      );
    });

    test('категория вставляется после заголовка', () {
      expect(
        spoken(currentPeriod(PeriodKind.month, _today), category: 'Кафе'),
        'Расходы по дням, категория Кафе, за октябрь',
      );
    });

    test('пустое состояние с категорией и озвучка чипа', () {
      expect(
        dynamicsCategoryNothingText('Кафе', TransactionType.expense),
        'В категории «Кафе» за этот период расходов нет',
      );
      expect(
        dynamicsCategoryNothingText('Подарки', TransactionType.income),
        'В категории «Подарки» за этот период доходов нет',
      );
      expect(
        dynamicsCategoryChipSpoken('Все категории'),
        'Категория: Все категории, изменить',
      );
    });
  });
}
