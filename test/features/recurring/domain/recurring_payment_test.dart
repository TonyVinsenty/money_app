import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/domain/recurring_rules.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

RecurringPayment make({
  String id = 'p1',
  String title = 'Интернет',
  TransactionType type = TransactionType.expense,
  Money? amount,
  String categoryId = 'c1',
  String? subcategoryId,
  String? accountId,
  RepeatUnit unit = RepeatUnit.month,
  int every = 1,
  DateOnly? startsOn,
  DateOnly? endsOn,
  bool remind = true,
  DateOnly? trackedThrough,
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? deletedAt,
}) {
  return RecurringPayment(
    id: id,
    title: title,
    type: type,
    amount: amount ?? Money.fromMinor(65000, 'RUB'),
    categoryId: categoryId,
    subcategoryId: subcategoryId,
    accountId: accountId,
    unit: unit,
    every: every,
    startsOn: startsOn ?? DateOnly(2026, 11, 5),
    endsOn: endsOn,
    remind: remind,
    trackedThrough: trackedThrough,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
  );
}

void expectRule(void Function() body, RecurringRule rule) {
  expect(
    body,
    throwsA(isA<RecurringRuleException>().having((e) => e.rule, 'rule', rule)),
  );
}

void main() {
  group('название', () {
    test('пробелы по краям обрезаются', () {
      expect(make(title: '  Интернет \n').title, 'Интернет');
    });

    test('пустое и из пробелов - emptyTitle', () {
      expectRule(() => make(title: ''), RecurringRule.emptyTitle);
      expectRule(() => make(title: '   '), RecurringRule.emptyTitle);
    });

    test('40 символов можно, 41 - titleTooLong', () {
      expect(make(title: 'я' * 40).title.length, 40);
      expectRule(() => make(title: 'я' * 41), RecurringRule.titleTooLong);
    });

    test('длина считается в символах, а не в кодовых единицах', () {
      expect(make(title: '\u{1F600}' * 40).title.runes.length, 40);
      expectRule(
        () => make(title: '\u{1F600}' * 41),
        RecurringRule.titleTooLong,
      );
    });

    test('пробелы не считаются в длину', () {
      expect(make(title: ' ${'я' * 40} ').title.length, 40);
    });
  });

  group('сумма и валюта', () {
    test('ноль и отрицательная - nonPositiveAmount', () {
      expectRule(
        () => make(amount: Money.zero('RUB')),
        RecurringRule.nonPositiveAmount,
      );
      expectRule(
        () => make(amount: Money.fromMinor(-1, 'RUB')),
        RecurringRule.nonPositiveAmount,
      );
    });

    test('одна минорная единица допустима', () {
      expect(make(amount: Money.fromMinor(1, 'USD')).amount.minorUnits, 1);
    });

    test('криптовалюта и своя валюта - currencyNotRegular', () {
      expectRule(
        () => make(amount: Money.fromMinor(100, 'BTC')),
        RecurringRule.currencyNotRegular,
      );
      expectRule(
        () => make(amount: Money.fromMinor(100, 'MYPOINTS')),
        RecurringRule.currencyNotRegular,
      );
    });
  });

  group('повтор и даты', () {
    test('every: 1 и 99 можно, 0 и 100 - everyOutOfRange', () {
      expect(make(every: 1).every, 1);
      expect(make(every: 99).every, 99);
      expectRule(() => make(every: 0), RecurringRule.everyOutOfRange);
      expectRule(() => make(every: 100), RecurringRule.everyOutOfRange);
      expectRule(() => make(every: -3), RecurringRule.everyOutOfRange);
    });

    test('endsOn в день старта можно, за день до - endsBeforeStart', () {
      final start = DateOnly(2026, 11, 5);
      expect(make(startsOn: start, endsOn: start).endsOn, start);
      expectRule(
        () => make(startsOn: start, endsOn: start.addDays(-1)),
        RecurringRule.endsBeforeStart,
      );
    });
  });

  group('идентификаторы', () {
    test('пустые id - emptyId', () {
      expectRule(() => make(id: ' '), RecurringRule.emptyId);
      expectRule(() => make(categoryId: ''), RecurringRule.emptyId);
      expectRule(() => make(subcategoryId: ''), RecurringRule.emptyId);
      expectRule(() => make(accountId: ' '), RecurringRule.emptyId);
    });
  });

  group('моменты времени', () {
    test('не UTC - ArgumentError', () {
      final local = DateTime(2026, 10, 10);
      expect(() => make(createdAt: local), throwsArgumentError);
      expect(() => make(updatedAt: local), throwsArgumentError);
      expect(() => make(deletedAt: local), throwsArgumentError);
    });

    test('UTC принимается; isDeleted по deletedAt', () {
      final at = DateTime.utc(2026, 10, 10);
      expect(make(createdAt: at).isDeleted, isFalse);
      expect(make(deletedAt: at).isDeleted, isTrue);
    });
  });

  group('копии with...', () {
    test('меняют одно поле, остальные остаются', () {
      final base = make(
        subcategoryId: 's1',
        accountId: 'a1',
        endsOn: DateOnly(2027, 1, 1),
        trackedThrough: DateOnly(2026, 11, 4),
      );
      expect(base.withTitle(' Связь ').title, 'Связь');
      expect(
        base.withType(TransactionType.income).type,
        TransactionType.income,
      );
      expect(
        base.withAmount(Money.fromMinor(1, 'EUR')).amount,
        Money.fromMinor(1, 'EUR'),
      );
      expect(base.withRemind(false).remind, isFalse);
      expect(base.withRepeat(RepeatUnit.year, 2).unit, RepeatUnit.year);
      expect(base.withRepeat(RepeatUnit.year, 2).every, 2);
      expect(base.withTitle('X').accountId, 'a1');
      expect(base.withTitle('X').endsOn, DateOnly(2027, 1, 1));
      expect(base.withTitle('X').id, 'p1');
    });

    test('обнуляемые поля можно очистить', () {
      final base = make(
        subcategoryId: 's1',
        accountId: 'a1',
        endsOn: DateOnly(2027, 1, 1),
        trackedThrough: DateOnly(2026, 11, 4),
      );
      expect(base.withSubcategory(null).subcategoryId, isNull);
      expect(base.withAccount(null).accountId, isNull);
      expect(base.withEndsOn(null).endsOn, isNull);
      expect(base.withTrackedThrough(null).trackedThrough, isNull);
    });

    test('смена категории сбрасывает подкатегорию', () {
      final copy = make(subcategoryId: 's1').withCategory('c2');
      expect(copy.categoryId, 'c2');
      expect(copy.subcategoryId, isNull);
    });

    test('копия проверяет правила', () {
      final base = make();
      expectRule(() => base.withTitle(''), RecurringRule.emptyTitle);
      expectRule(
        () => base.withAmount(Money.zero('RUB')),
        RecurringRule.nonPositiveAmount,
      );
      expectRule(
        () => base.withRepeat(RepeatUnit.week, 100),
        RecurringRule.everyOutOfRange,
      );
      expectRule(
        () => base.withEndsOn(DateOnly(2026, 11, 4)),
        RecurringRule.endsBeforeStart,
      );
      expectRule(
        () => base
            .withStartsOn(DateOnly(2026, 11, 6))
            .withEndsOn(DateOnly(2026, 11, 5)),
        RecurringRule.endsBeforeStart,
      );
    });

    test('deleted и restored', () {
      final at = DateTime.utc(2026, 10, 10);
      final gone = make().deleted(at);
      expect(gone.deletedAt, at);
      expect(gone.restored().deletedAt, isNull);
      expect(() => make().deleted(DateTime(2026)), throwsArgumentError);
    });

    test('createdAt и updatedAt сохраняются в копиях', () {
      final at = DateTime.utc(2026, 10, 1);
      final copy = make(createdAt: at, updatedAt: at).withRemind(false);
      expect(copy.createdAt, at);
      expect(copy.updatedAt, at);
    });
  });

  group('равенство', () {
    test('одинаковые поля - равны и с одним hashCode', () {
      final a = make(subcategoryId: 's1', endsOn: DateOnly(2027, 1, 1));
      final b = make(subcategoryId: 's1', endsOn: DateOnly(2027, 1, 1));
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('любое отличие делает платежи разными', () {
      final base = make();
      expect(base == make(id: 'p2'), isFalse);
      expect(base == make(title: 'Связь'), isFalse);
      expect(base == make(type: TransactionType.income), isFalse);
      expect(base == make(amount: Money.fromMinor(1, 'RUB')), isFalse);
      expect(base == make(categoryId: 'c2'), isFalse);
      expect(base == make(subcategoryId: 's1'), isFalse);
      expect(base == make(accountId: 'a1'), isFalse);
      expect(base == make(unit: RepeatUnit.week), isFalse);
      expect(base == make(every: 2), isFalse);
      expect(base == make(startsOn: DateOnly(2026, 11, 6)), isFalse);
      expect(base == make(endsOn: DateOnly(2027, 1, 1)), isFalse);
      expect(base == make(remind: false), isFalse);
      expect(base == make(trackedThrough: DateOnly(2026, 11, 4)), isFalse);
      expect(base == make(deletedAt: DateTime.utc(2026, 10, 10)), isFalse);
    });

    test('createdAt и updatedAt в равенство не входят', () {
      final at = DateTime.utc(2026, 10, 1);
      expect(make(createdAt: at, updatedAt: at), make());
    });
  });

  test('исключение несёт правило и сообщение', () {
    final e = RecurringRuleException(RecurringRule.emptyTitle);
    expect(e.toString(), contains('emptyTitle'));
    for (final rule in RecurringRule.values) {
      expect(RecurringRuleException(rule).message, isNotEmpty);
    }
  });
}
