import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/recurring/domain/recurring_payment.dart';
import 'package:money_app/features/recurring/domain/reminder_plan.dart';
import 'package:money_app/features/transactions/domain/transaction_type.dart';

RecurringPayment _payment({
  String id = 'p1',
  String title = 'Интернет',
  TransactionType type = TransactionType.expense,
  DateOnly? startsOn,
  RepeatUnit unit = RepeatUnit.month,
  DateOnly? endsOn,
  bool remind = true,
  DateTime? deletedAt,
}) {
  return RecurringPayment(
    id: id,
    title: title,
    type: type,
    amount: Money.fromMinor(65000, 'RUB'),
    categoryId: 'c1',
    unit: unit,
    every: 1,
    startsOn: startsOn ?? DateOnly(2026, 10, 20),
    endsOn: endsOn,
    remind: remind,
    deletedAt: deletedAt,
  );
}

List<ReminderItem> _plan(
  List<RecurringPayment> payments, {
  Set<String> paid = const {},
  DateTime? now,
  ReminderTime? time,
  int budget = 40,
}) {
  return planReminders(
    payments: payments,
    paidTodayIds: paid,
    categoryNames: const {'c1': 'Связь'},
    now: now ?? DateTime(2026, 10, 10, 8, 0),
    time: time ?? ReminderTime(10, 0),
    budget: budget,
  );
}

void main() {
  test('текст и местное время без UTC', () {
    final items = _plan([_payment()]);
    // 20 октября и 20 ноября (горизонт 60 дней до 9 декабря).
    expect(items.map((i) => '${i.month}-${i.day}'), ['10-20', '11-20']);
    final first = items.first;
    expect(first.id, 0);
    expect((first.hour, first.minute), (10, 0));
    expect(first.title, 'Платёж сегодня: Интернет');
    expect(first.body, 'Расход 650,00 ₽ · Связь');
    expect(first.toMap().keys, [
      'id',
      'year',
      'month',
      'day',
      'hour',
      'minute',
      'title',
      'body',
    ]);
  });

  test('доход и неизвестная категория', () {
    final items = planReminders(
      payments: [_payment(type: TransactionType.income)],
      paidTodayIds: const {},
      categoryNames: const {},
      now: DateTime(2026, 10, 10, 8),
      time: ReminderTime(9, 30),
    );
    expect(items.first.body, 'Доход 650,00 ₽');
    expect((items.first.hour, items.first.minute), (9, 30));
  });

  test('бюджет: берутся ближайшие по дате', () {
    final payments = [
      for (var i = 0; i < 50; i++)
        _payment(
          id: 'p$i',
          title: 'П$i',
          startsOn: DateOnly(2026, 10, 11).addDays(i % 25),
          unit: RepeatUnit.week,
        ),
    ];
    final items = _plan(payments);
    expect(items.length, 40);
    expect([for (final i in items) i.id], List.generate(40, (i) => i));
    final days = [for (final i in items) DateOnly(i.year, i.month, i.day)];
    expect(days, [...days]..sort());
    // Первые 40 совпадают с началом полного списка (ближайшие).
    final all = _plan(payments, budget: 1000);
    expect(all.length, greaterThan(40));
    expect(items, all.sublist(0, 40));
    expect(_plan(payments, budget: 0), isEmpty);
  });

  test('сегодняшний: до времени планируется, после - нет', () {
    final p = _payment(startsOn: DateOnly(2026, 10, 10), unit: RepeatUnit.year);
    expect(_plan([p], now: DateTime(2026, 10, 10, 9, 59)).length, 1);
    expect(_plan([p], now: DateTime(2026, 10, 10, 10, 0)), isEmpty);
    expect(_plan([p], now: DateTime(2026, 10, 10, 18, 0)), isEmpty);
  });

  test('оплаченный сегодня не планируется, следующая дата остаётся', () {
    final p = _payment(startsOn: DateOnly(2026, 10, 10), unit: RepeatUnit.week);
    final items = _plan([p], paid: {'p1'});
    expect(items.first.day, 17);
  });

  test('заголовок: расход - платёж, доход - поступление', () {
    final expense = _plan([_payment(title: 'Интернет')]).first;
    final income = _plan([
      _payment(title: 'Зарплата', type: TransactionType.income),
    ]).first;
    expect(expense.title, 'Платёж сегодня: Интернет');
    expect(income.title, 'Поступление сегодня: Зарплата');
  });

  test('после endsOn напоминаний нет', () {
    final p = _payment(
      startsOn: DateOnly(2026, 10, 12),
      unit: RepeatUnit.week,
      endsOn: DateOnly(2026, 10, 26),
    );
    final items = _plan([p]);
    expect(items.map((i) => '${i.month}-${i.day}'), [
      '10-12',
      '10-19',
      '10-26',
    ]);
  });

  test('переход декабрь - январь', () {
    final p = _payment(startsOn: DateOnly(2026, 12, 20));
    final items = _plan([p], now: DateTime(2026, 12, 15, 8));
    expect(items.map((i) => '${i.year}-${i.month}-${i.day}'), [
      '2026-12-20',
      '2027-1-20',
    ]);
  });

  test('ежемесячный на 31-е: в коротком месяце последний день', () {
    final p = _payment(startsOn: DateOnly(2026, 1, 31));
    final items = _plan([p], now: DateTime(2026, 2, 1, 8));
    expect(items.map((i) => '${i.month}-${i.day}'), ['2-28', '3-31']);
  });

  test('remind = false и удалённый - нет', () {
    expect(_plan([_payment(remind: false)]), isEmpty);
    expect(_plan([_payment(deletedAt: DateTime.utc(2026, 10, 1))]), isEmpty);
  });

  test('горизонт 60 дней включительно', () {
    final inside = _payment(startsOn: DateOnly(2026, 12, 9));
    final outside = _payment(startsOn: DateOnly(2026, 12, 10));
    expect(_plan([inside]).length, 1);
    expect(_plan([outside]), isEmpty);
  });

  test('ReminderTime проверяет границы', () {
    expect(() => ReminderTime(24, 0), throwsArgumentError);
    expect(() => ReminderTime(0, 60), throwsArgumentError);
    expect(ReminderTime(9, 5).toString(), '09:05');
  });
}
