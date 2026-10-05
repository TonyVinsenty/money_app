import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/core/time/period.dart';
import 'package:money_app/features/analytics/domain/analytics_period.dart';
import 'package:money_app/features/analytics/presentation/analytics_controller.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

class _Counter {
  _Counter(AnalyticsController controller) {
    controller.addListener(() => count++);
  }

  int count = 0;
}

void main() {
  final today = DateOnly(2026, 10, 4);

  AnalyticsController make({DateOnly? firstDay, DateOnly? at}) =>
      AnalyticsController(today: at ?? today, firstDay: firstDay);

  group('начальное состояние', () {
    test('по умолчанию текущий месяц', () {
      final c = make();

      expect(c.period, currentPeriod(PeriodKind.month, today));
      expect(c.period.range, monthRange(DateOnly(2026, 10, 1)));
      expect(c.today, today);
      expect(c.firstDay, isNull);
    });

    test('firstDay из конструктора', () {
      expect(
        make(firstDay: DateOnly(2026, 3, 1)).firstDay,
        DateOnly(2026, 3, 1),
      );
    });
  });

  group('смена вида', () {
    test('неделя 28.09-04.10 → октябрь (опора на сегодня)', () {
      final c = make()..selectKind(PeriodKind.week);
      expect(c.period.range, DateRange(DateOnly(2026, 9, 28), today));

      c.selectKind(PeriodKind.month);
      expect(c.period, currentPeriod(PeriodKind.month, today));
    });

    test('неделя 21.09-27.09 → сентябрь', () {
      final c = make(firstDay: DateOnly(2026, 1, 1))
        ..selectKind(PeriodKind.week)
        ..previous();
      expect(
        c.period.range,
        DateRange(DateOnly(2026, 9, 21), DateOnly(2026, 9, 27)),
      );

      c.selectKind(PeriodKind.month);

      expect(c.period.range, monthRange(DateOnly(2026, 9, 1)));
    });

    test('день 15.09 → неделя 14.09-20.09', () {
      final c = make(firstDay: DateOnly(2026, 1, 1))
        ..selectKind(PeriodKind.day);
      while (c.period.range.start != DateOnly(2026, 9, 15)) {
        c.previous();
      }

      c.selectKind(PeriodKind.week);

      expect(
        c.period.range,
        DateRange(DateOnly(2026, 9, 14), DateOnly(2026, 9, 20)),
      );
    });

    test('год и день', () {
      final c = make()..selectKind(PeriodKind.year);
      expect(c.period.range, yearRange(today));

      c.selectKind(PeriodKind.day);
      expect(c.period.range, dayRange(today));
    });

    test('тот же вид не уведомляет', () {
      final c = make();
      final counter = _Counter(c);

      c.selectKind(PeriodKind.month);

      expect(counter.count, 0);
    });

    test('смена вида уведомляет один раз', () {
      final c = make();
      final counter = _Counter(c);

      c.selectKind(PeriodKind.week);

      expect(counter.count, 1);
    });

    test('custom — ArgumentError', () {
      final c = make();
      final counter = _Counter(c);

      expect(() => c.selectKind(PeriodKind.custom), throwsArgumentError);
      expect(counter.count, 0);
      expect(c.period.kind, PeriodKind.month);
    });
  });

  group('назад и вперёд', () {
    test('назад при firstDay == null нельзя', () {
      final c = make();
      final counter = _Counter(c);

      expect(c.canGoBack, isFalse);
      c.previous();

      expect(c.period, currentPeriod(PeriodKind.month, today));
      expect(counter.count, 0);
    });

    test('назад нельзя на периоде первой операции', () {
      final c = make(firstDay: DateOnly(2026, 10, 2));

      expect(c.canGoBack, isFalse);
    });

    test('назад можно, когда первая операция раньше', () {
      final c = make(firstDay: DateOnly(2026, 9, 30));
      final counter = _Counter(c);

      expect(c.canGoBack, isTrue);
      c.previous();

      expect(c.period.range, monthRange(DateOnly(2026, 9, 1)));
      expect(counter.count, 1);
      expect(c.canGoBack, isFalse);
    });

    test('назад до периода первой операции включительно (неделя)', () {
      final c = make(firstDay: DateOnly(2026, 9, 22))
        ..selectKind(PeriodKind.week);

      expect(c.canGoBack, isTrue);
      c.previous();
      expect(
        c.period.range,
        DateRange(DateOnly(2026, 9, 21), DateOnly(2026, 9, 27)),
      );
      expect(c.canGoBack, isFalse);
    });

    test('вперёд с текущего нельзя', () {
      final c = make();
      final counter = _Counter(c);

      expect(c.canGoForward, isFalse);
      c.next();

      expect(c.period, currentPeriod(PeriodKind.month, today));
      expect(counter.count, 0);
    });

    test('вперёд после шага назад возвращает на текущий', () {
      final c = make(firstDay: DateOnly(2026, 1, 1))..previous();
      final counter = _Counter(c);

      expect(c.canGoForward, isTrue);
      c.next();

      expect(c.period, currentPeriod(PeriodKind.month, today));
      expect(counter.count, 1);
    });

    test('первая операция ещё неизвестна: вперёд можно, как раньше', () {
      final c = make(firstDay: DateOnly(2026, 1, 1))..previous();

      c.updateFirstDay(null, known: false);

      expect(c.canGoForward, isTrue);
    });

    test('без операций (день первой операции пропал) вперёд нельзя', () {
      final c = make(firstDay: DateOnly(2026, 1, 1))..previous();

      c.updateFirstDay(null);

      expect(c.canGoBack, isFalse);
      expect(c.canGoForward, isFalse);
    });
  });

  group('updateToday', () {
    test('тот же день не уведомляет', () {
      final c = make();
      final counter = _Counter(c);

      c.updateToday(today);

      expect(counter.count, 0);
    });

    test('через полночь в пределах месяца: текущий остаётся текущим', () {
      final c = make();
      final counter = _Counter(c);

      c.updateToday(DateOnly(2026, 10, 5));

      expect(c.today, DateOnly(2026, 10, 5));
      expect(c.period, currentPeriod(PeriodKind.month, DateOnly(2026, 10, 5)));
      expect(counter.count, 1);
    });

    test('смена месяца: был текущий → новый текущий', () {
      final c = make();
      final counter = _Counter(c);

      c.updateToday(DateOnly(2026, 11, 1));

      expect(c.period.range, monthRange(DateOnly(2026, 11, 1)));
      expect(counter.count, 1);
    });

    test('смена месяца: была текущая неделя → новая текущая неделя', () {
      final c = make()..selectKind(PeriodKind.week);

      c.updateToday(DateOnly(2026, 10, 5));

      expect(
        c.period.range,
        DateRange(DateOnly(2026, 10, 5), DateOnly(2026, 10, 11)),
      );
    });

    test('был прошлый период → остаётся', () {
      final c = make(firstDay: DateOnly(2026, 1, 1))..previous();
      final counter = _Counter(c);

      c.updateToday(DateOnly(2026, 11, 1));

      expect(c.period.range, monthRange(DateOnly(2026, 9, 1)));
      expect(c.today, DateOnly(2026, 11, 1));
      expect(counter.count, 1);
    });
  });

  group('updateFirstDay', () {
    test('новое значение уведомляет один раз и открывает «назад»', () {
      final c = make();
      final counter = _Counter(c);

      c.updateFirstDay(DateOnly(2026, 5, 1));

      expect(c.firstDay, DateOnly(2026, 5, 1));
      expect(c.canGoBack, isTrue);
      expect(counter.count, 1);
    });

    test('то же значение не уведомляет', () {
      final c = make(firstDay: DateOnly(2026, 5, 1));
      final counter = _Counter(c);

      c.updateFirstDay(DateOnly(2026, 5, 1));
      expect(counter.count, 0);

      final empty = make();
      final emptyCounter = _Counter(empty);
      empty.updateFirstDay(null);
      expect(emptyCounter.count, 0);
    });

    test('период не двигается, даже если стал раньше первой операции', () {
      final c = make(firstDay: DateOnly(2026, 1, 1))..previous();

      c.updateFirstDay(DateOnly(2026, 10, 2));

      expect(c.period.range, monthRange(DateOnly(2026, 9, 1)));
      expect(c.canGoBack, isFalse);
    });
  });

  group('свой интервал', () {
    final start = DateOnly(2026, 9, 1);
    final end = DateOnly(2026, 9, 15);

    test('выбор меняет период и уведомляет один раз', () {
      final c = make();
      final counter = _Counter(c);

      c.selectCustomRange(start, end);

      expect(
        c.period,
        AnalyticsPeriod(PeriodKind.custom, DateRange(start, end)),
      );
      expect(counter.count, 1);
    });

    test('тот же интервал не уведомляет', () {
      final c = make()..selectCustomRange(start, end);
      final counter = _Counter(c);

      c.selectCustomRange(start, end);

      expect(counter.count, 0);
    });

    test('конец в будущем и конец раньше начала: ArgumentError', () {
      final c = make();
      final counter = _Counter(c);

      expect(
        () => c.selectCustomRange(start, today.addDays(1)),
        throwsArgumentError,
      );
      expect(() => c.selectCustomRange(end, start), throwsArgumentError);
      expect(c.period.kind, PeriodKind.month);
      expect(counter.count, 0);
    });

    test('конец интервала — сегодня: можно', () {
      final c = make()..selectCustomRange(start, today);

      expect(c.period.range.end, today);
    });

    test('стрелки недоступны, previous/next ничего не делают', () {
      final c = make(firstDay: DateOnly(2026, 1, 1))
        ..selectCustomRange(start, end);
      final counter = _Counter(c);

      expect(c.canGoBack, isFalse);
      expect(c.canGoForward, isFalse);
      c.previous();
      c.next();
      expect(counter.count, 0);
    });

    test('переход на месяц берёт месяц конца интервала', () {
      final c = make()
        ..selectCustomRange(DateOnly(2026, 8, 20), DateOnly(2026, 9, 15))
        ..selectKind(PeriodKind.month);

      expect(c.period, currentPeriod(PeriodKind.month, DateOnly(2026, 9, 15)));
    });

    test('смена «сегодня» свой интервал не двигает', () {
      final c = make()..selectCustomRange(start, end);

      c.updateToday(DateOnly(2026, 11, 1));

      expect(c.period.range, DateRange(start, end));
    });
  });

  group('тип операций', () {
    test('по умолчанию расходы', () {
      expect(make().type, TransactionType.expense);
    });

    test('смена типа уведомляет один раз, тот же тип — нет', () {
      final c = make();
      final counter = _Counter(c);

      c.selectType(TransactionType.income);
      expect(c.type, TransactionType.income);
      expect(counter.count, 1);

      c.selectType(TransactionType.income);
      expect(counter.count, 1);
    });

    test('тип сохраняется при смене периода, вида и своего интервала', () {
      final c = make(firstDay: DateOnly(2026, 1, 1))
        ..selectType(TransactionType.income)
        ..previous();
      expect(c.type, TransactionType.income);

      c.selectKind(PeriodKind.week);
      expect(c.type, TransactionType.income);

      c.selectCustomRange(DateOnly(2026, 9, 1), DateOnly(2026, 9, 15));
      expect(c.type, TransactionType.income);

      c.selectKind(PeriodKind.month);
      expect(c.type, TransactionType.income);
    });
  });
}
