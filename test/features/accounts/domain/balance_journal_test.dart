import 'package:flutter_test/flutter_test.dart';
import 'package:money_app/core/money/money.dart';
import 'package:money_app/core/time/date_only.dart';
import 'package:money_app/features/accounts/domain/account.dart';
import 'package:money_app/features/accounts/domain/balance_journal.dart';
import 'package:money_app/features/accounts/domain/transfer.dart';

// Фиксированный день: не зависит от пояса машины (берём UTC-дату момента).
DateOnly utcDay(DateTime m) => DateOnly(m.year, m.month, m.day);

Account acc(
  String id, {
  DateTime? createdAt,
  DateTime? archivedAt,
  String currency = 'RUB',
}) => Account(
  id: id,
  name: 'Счёт $id',
  iconKey: 'wallet',
  openingBalance: Money.zero(currency),
  sortOrder: 0,
  currencyDigits: 2,
  createdAt: createdAt,
  archivedAt: archivedAt,
);

Transfer tr(String id, DateOnly on, DateTime at, {String from = 'a'}) =>
    Transfer(
      id: id,
      fromAccountId: from,
      toAccountId: 'b',
      amount: Money.fromMinor(100, 'RUB'),
      occurredOn: on,
      occurredAt: at,
    );

List<BalanceJournalEntry> build(List<Account> a, List<Transfer> t) =>
    buildBalanceJournal(a, t, dayOf: utcDay);

String label(BalanceJournalEntry e) => switch (e) {
  AccountCreatedEntry() => 'created:${e.id}',
  AccountArchivedEntry() => 'archived:${e.id}',
  TransferEntry() => 'transfer:${e.id}',
};

void main() {
  final d1 = DateTime.utc(2026, 10, 1, 10);
  final d5 = DateTime.utc(2026, 10, 5, 10);
  final d7 = DateTime.utc(2026, 10, 7, 10);

  test('пусто: нет счетов и переводов - пустой журнал', () {
    expect(build([], []), isEmpty);
  });

  test('один счёт - одна строка «Создан» с днём и моментом', () {
    final r = build([acc('a', createdAt: d1)], []);
    expect(r.map(label), ['created:a']);
    expect(r.single.day, DateOnly(2026, 10, 1));
    expect(r.single.moment, d1);
  });

  test('счёт без createdAt строки «Создан» не даёт', () {
    expect(build([acc('a')], []), isEmpty);
  });

  test('архивный счёт: «Создан» и «В архив», архив выше', () {
    final r = build([acc('a', createdAt: d1, archivedAt: d5)], []);
    expect(r.map(label), ['archived:a', 'created:a']);
    expect(r.first.day, DateOnly(2026, 10, 5));
  });

  test('перевод стоит по своему occurredOn между событиями счетов', () {
    final r = build(
      [acc('a', createdAt: d1, archivedAt: d7), acc('b', createdAt: d1)],
      [tr('t1', DateOnly(2026, 10, 5), d5)],
    );
    expect(r.map(label), [
      'archived:a',
      'transfer:t1',
      'created:a',
      'created:b',
    ]);
  });

  test('перевод задним числом оказывается ниже создания счёта', () {
    final r = build(
      [acc('a', createdAt: d5)],
      [tr('t1', DateOnly(2026, 10, 1), d1)],
    );
    expect(r.map(label), ['created:a', 'transfer:t1']);
  });

  test('день решает раньше момента (occurredOn важнее occurredAt)', () {
    final r = build(
      [acc('a', createdAt: d5)],
      [tr('t1', DateOnly(2026, 10, 5), DateTime.utc(2026, 10, 5, 1))],
    );
    // Тот же день, перевод раньше по моменту - ниже создания.
    expect(r.map(label), ['created:a', 'transfer:t1']);
  });

  test('равный момент: вид (в архив, перевод, создан), затем id', () {
    final r = build(
      [acc('b', createdAt: d5), acc('a', createdAt: d5, archivedAt: d5)],
      [
        tr('t2', DateOnly(2026, 10, 5), d5),
        tr('t1', DateOnly(2026, 10, 5), d5),
      ],
    );
    expect(r.map(label), [
      'archived:a',
      'transfer:t1',
      'transfer:t2',
      'created:a',
      'created:b',
    ]);
  });

  test('порядок не зависит от порядка входных списков', () {
    final accounts = [acc('a', createdAt: d5), acc('b', createdAt: d5)];
    final transfers = [
      tr('t1', DateOnly(2026, 10, 5), d5),
      tr('t2', DateOnly(2026, 10, 5), d5),
    ];
    expect(
      build(accounts.reversed.toList(), transfers.reversed.toList()).map(label),
      build(accounts, transfers).map(label),
    );
  });

  test('счета разных валют попадают в журнал', () {
    final r = build([
      acc('a', createdAt: d1, currency: 'USD'),
      acc('b', createdAt: d5, currency: 'BTC'),
    ], []);
    expect(r.map(label), ['created:b', 'created:a']);
  });

  test('dayOf по умолчанию берёт местный день момента', () {
    final r = buildBalanceJournal([acc('a', createdAt: d1)], []);
    expect(r.single.day, DateOnly.fromDateTime(d1));
  });
}
